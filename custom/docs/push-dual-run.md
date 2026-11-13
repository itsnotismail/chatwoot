# Push dual run: the Comvor Agent app and the official Chatwoot app side by side

Code: `custom/app/services/custom/notification/push_notification_service.rb`, prepended into `Notification::PushNotificationService` (hook in `custom/UPSTREAM_EDITS.md`, section 2).

## Routing

Each FCM subscription is routed on its own. Browser push is unchanged.

| Firebase config (`FIREBASE_PROJECT_ID` + `FIREBASE_CREDENTIALS`) | `ENABLE_PUSH_RELAY_SERVER` | Subscription `app_id == com.comvor.agent` | Any other FCM subscription |
|---|---|---|---|
| absent or blank | true | hub | hub |
| absent or blank | false | nothing | nothing |
| present | true | **direct FCM v1** (Comvor's project) | hub |
| present | false | direct FCM v1 | direct FCM v1 (upstream's behaviour) |

The first two rows are exactly upstream's behaviour. Upstream sends nothing through the hub once the Firebase config is present, which would silence every agent on the official app; the third row is the change.

The app tags itself by sending `subscription_attributes.app_id` in `POST /api/v1/notification_subscriptions` (the controller permits `subscription_attributes` open-ended). A device that re-registers without the tag loses it, because the builder replaces the attributes.

A direct send removes the subscription only when FCM v1 answers `UNREGISTERED` (any subscription) or `SENDER_ID_MISMATCH` (a `com.comvor.agent` subscription only) in a `google.firebase.fcm.v1.FcmError` detail. An official-app token sent direct (row 4) always gets `SENDER_ID_MISMATCH` and is kept, so a relay-off flip does not wipe official-app subscriptions. Any other answer (429, 5xx, 400, 401, a 404 or 403 without that detail, a non-JSON body) or an exception keeps the subscription, logs it and reports it to Sentry. That push is not retried: re-raising would make Sidekiq resend the hub pushes in the same job. Consequence: a service account from the WRONG Firebase project gets `SENDER_ID_MISMATCH` for every Comvor app token and removes those subscriptions. The app re-registers at its next sign-in, so check the project before switching it on.

## Where the Firebase config really comes from

`GlobalConfigService.load` reads the `installation_configs` row first. Only when the row's value is blank does it look at the env var, and then it calls `first_or_create(value: ENV)`, which writes the env value **only if no row exists**. `db:migrate` (and so `db:chatwoot_prepare` on every deploy) runs `ConfigLoader`, which seeds an empty `FIREBASE_PROJECT_ID` and `FIREBASE_CREDENTIALS` row. So:

- **On an installation that has migrated since these rows were added (dev, verified; prod presumably): the env vars are ignored.** Setting `FIREBASE_*` in the deploy env does not switch direct FCM on. Set the values in Super Admin, Settings, App Config (general), where both keys are listed.
- **On a database with no row:** the first `load` copies the env value into a new row, and from then on the row wins. Removing the env var does not switch it off.
- A row blanked in Super Admin while the env var is still set makes `load` return `''`. The dual-run code treats `''` as absent (upstream treats it as present).

`spec/custom/lib/global_config_service_firebase_spec.rb` pins each of these.

## Switching on (owner, prod)

1. Firebase project with the Android app `com.comvor.agent` (and later iOS, with the APNs key). The service-account JSON is a secret: Bitwarden, never a tool call or a commit.
2. Super Admin, App Config (general): set `FIREBASE_PROJECT_ID` and `FIREBASE_CREDENTIALS`. Keep `ENABLE_PUSH_RELAY_SERVER: "true"` in comvor-deploy, or the official app loses push.
3. Sign in on the Comvor Agent app; check its `notification_subscriptions` row has `app_id`. Assign it a conversation and look for `FCM push sent to` in the Sidekiq log.

## Rollback (the trap)

Removing `FIREBASE_*` from comvor-deploy is **not** a rollback: the values live in `installation_configs`. To switch direct FCM off:

1. Clear both values in the row, not just the env var. In a Rails console: `InstallationConfig.where(name: %w[FIREBASE_PROJECT_ID FIREBASE_CREDENTIALS]).find_each { |c| c.update!(value: nil) }` (its `after_commit` clears the `GlobalConfig` cache). Blanking them in Super Admin also works with this code; with upstream's code alone, a blank plus a leftover env var counts as configured.
2. Remove `FIREBASE_*` from the deploy env as well, so a fresh database does not copy them back.
3. Comvor app subscriptions then go through the hub, which cannot reach their tokens: those agents get no push until it is switched back on. Official-app agents are unaffected throughout.
4. **Rolling back this code** (reverting the fork commit) while the values are still set brings back upstream's routing: everything direct, nothing through the hub, so every official-app agent loses push. Clear the values first.
