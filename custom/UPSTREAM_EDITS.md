# Upstream edits: the checklist for every Chatwoot merge

Comvor's own behaviour lives in `custom/`, which is Chatwoot's own extension folder. Upstream files carry only the hook lines and the edits listed here. Work through this file on every upstream merge, and keep it current: any new edit to a non-`custom/` file gets a row here, in the same commit.

`00837019b5` is the upstream commit the fork last took `enterprise/` from. Line numbers below are as of the commit that last touched this file. Find each edit again by the `Comvor` comment next to it, or by `git log --oneline 00837019b5..HEAD -- <path>`.

## 1. Rules for the merge itself

1. **Resolve every conflict in `enterprise/**` and `spec/enterprise/**` by taking upstream's side.** Comvor has no edits there. Afterwards, `git diff <upstream-commit> HEAD -- enterprise spec/enterprise` must be empty.
   - Comvor code never goes under `enterprise/`. That folder is under Chatwoot's enterprise licence.
   - Comvor's tests never go under `spec/enterprise/`. Upstream's CE job deletes that folder.
2. **`custom/` and `spec/custom/` are Comvor's alone.** Upstream never ships them, so they never conflict.
3. **Work through sections 2 and 3:** keep each edit, or follow its own merge rule.
4. **Then run the verifiers in section 4.** A merge is done only when both modes pass.

## 2. Hook lines (one line or one guarded block each)

### Hooks Comvor added

| File:line | What | Why | Merge rule |
|---|---|---|---|
| `config/application.rb:54-62` | A guarded `if custom_root.exist?` block, right after the enterprise initializer require. It adds `custom/lib` and `custom/app/**` to the eager-load paths, unshifts `custom/app/views`, and requires `custom/config/initializers/**/*.rb`. | This is what loads `custom/`. | Keep the block **after** the enterprise block. That order makes custom views win, and makes custom initializers run after enterprise's. If upstream moves the enterprise block, move this one with it. |
| `lib/chatwoot_app.rb:38-39` | In `extensions`, the `custom?` branch reads `%w[enterprise custom].select { \|extension\| root.join(extension).exist? }`. Upstream's is a bare `%w[enterprise custom]`. | `each_extension_for` crashes (`false.const_defined?`) when a listed extension's namespace is undefined, which `Enterprise` is once the folder is deleted. | Keep it if upstream rewrites `extensions`. Drop it if upstream makes `const_get_maybe_false` safe for nil and false. |
| `app/controllers/dashboard_controller.rb:115` | `DashboardController.prepend_mod_with('DashboardController')` | The class had no hook. `Custom::DashboardController#allowed_login_methods` adds `saml` when `Comvor::SamlSso.available?`. That replaces fork commit `c7ac1411ed`, which was reverted: the method is upstream's again. | Keep. Drop it if upstream adds its own hook. `allowed_login_methods` is private: if upstream renames it, rename the override with it. |
| `app/controllers/api/v1/profiles_controller.rb:85` | `Api::V1::ProfilesController.prepend_mod_with('Api::V1::ProfilesController')` | The class had no hook. The prepended module refuses a `saml` user's password change. This replaces `c79b8f1808`'s hunk, which was reverted. | Keep. Drop it if upstream adds a hook. |
| `app/controllers/platform/api/v1/users_controller.rb:59` | `Platform::Api::V1::UsersController.prepend_mod_with('Platform::Api::V1::UsersController')` | The class had no hook. The prepended module refuses a Platform API `password` for a `saml` user (behaviour D). | Same as above. |
| `.dockerignore`, last 3 lines | Excludes `enterprise` and `spec/enterprise` from the image. | Production must carry no enterprise code (licence). `ChatwootApp.enterprise?` is then false and `IS_ENTERPRISE` is false. | Keep the lines on every merge. Remove them only to roll back phase 3. The folder must be absent, not empty: `extensions` keys off the folder existing, so an empty `enterprise/` stops boot. |
| `app/javascript/v3/helpers/RouteHelper.js:48` | `!(chatwootConfig.allowedLoginMethods \|\| []).includes('saml') &&` in `isEnterpriseOnlyPath` | `/app/login/sso` is gated on `requireEnterprise`. It must open when the server offers `saml`, enterprise or not. The frontend has no extension point. | Keep the line inside whatever condition gates `requireEnterprise` routes. Two examples in `specs/RouteHelper.spec.js` pin it; keep them too. |

### Upstream's own hooks that `custom/` depends on

These lines are unchanged upstream code. If upstream removes or renames one, the matching `Custom::` module silently stops loading.

| Upstream line | Used by |
|---|---|
| `DeviseOverrides::SessionsController.prepend_mod_with(...)` (`sessions_controller.rb:111`) | `Custom::DeviseOverrides::SessionsController`: password delegation, portal 2FA, sign-out hand-off |
| `DeviseOverrides::PasswordsController.prepend_mod_with(...)` (`passwords_controller.rb:44`) | `Custom::DeviseOverrides::PasswordsController` |
| `DeviseOverrides::OmniauthCallbacksController.prepend_mod_with(...)` (`omniauth_callbacks_controller.rb:107`) | `Custom::DeviseOverrides::OmniauthCallbacksController`: the comvor_saml callback and the mobile hand-off page |
| `User.include_mod_with('Concerns::User')` (`user.rb:222`) | `Custom::Concerns::User#generate_mobile_sso_deep_link` |
| `Account.include_mod_with('Concerns::Account')` (`account.rb:238`) | `Custom::Concerns::Account`, which adds `has_one :comvor_saml_setting` |
| `AccountUser.prepend_mod_with('AccountUser')` (`account_user.rb:93`) | `Custom::AccountUser`: inbox push flags |
| `Message.prepend_mod_with('Message')` (`message.rb:466`), `Conversation.prepend_mod_with('Conversation')` (`conversation.rb:361`) | `Custom::Message` and `Custom::Conversation`: merchant takeover |
| `config/initializers/01_inject_enterprise_edition_module.rb` (`each_extension_for`) | Every `Custom::` module. `ChatwootApp.custom?` adds `custom` to the extensions after `enterprise`, so ours is prepended last and comes first in the ancestor chain. |

### Mechanisms inside `custom/` (no upstream line)

- **Routes:** `custom/config/initializers/comvor_routes.rb` prepends Comvor's routes, so they win over `config/routes.rb` and over enterprise's routes for the same path. Prepended routes survive `reload_routes!`. Each route needs a unique `as:`, otherwise boot raises "route name already in use".
  - `config/routes.rb:89` (`resource :saml_settings`) is upstream's and is left alone. Ours answers first. In CE it names a missing controller, but nothing reaches it.
- **Rate limits:** `custom/config/initializers/comvor_rack_attack.rb`. It relies on upstream's `Rack::Attack` setup in `config/initializers/rack_attack.rb`, including the loopback and `RACK_ATTACK_ALLOWED_IPS` safelist, which skips every throttle.
- **Strings:** `custom/config/initializers/comvor_locales.rb` appends `custom/config/locales/**/*.yml` to the i18n load path, after `config/locales`. A key there overrides upstream's.
- **OmniAuth:** `custom/config/initializers/comvor_saml.rb` (the `comvor_saml` strategy) and `comvor_saml_idp_pin.rb` (the IdP pin on enterprise's settings model, where enterprise/ is present).

## 3. Comvor edits still in upstream files

### 3a. The SAML and portal work (spec Rule 3 table)

| File | Comvor commit(s) | Now | Merge rule |
|---|---|---|---|
| `app/controllers/devise_overrides/sessions_controller.rb` | `cd1c376639` | **Upstream.** Moved to `Custom::DeviseOverrides::SessionsController`. | Take upstream's. The module calls community helpers (`handle_mfa_required`, `render_mfa_error`, `sso_authentication_request?`) and devise_token_auth's `render_create_error_bad_credentials`. If upstream renames any of them, rename the call in the module; `spec/custom` fails loudly until you do. |
| `app/controllers/devise_overrides/omniauth_callbacks_controller.rb` | `f39a83ee62`, `50550bd640` | **Upstream.** The mobile hand-off page moved to `Custom::...OmniauthCallbacksController#sign_in_user_on_mobile`. | Take upstream's. **Mirror any upstream change to `sign_in_user_on_mobile` in the custom override.** It repeats upstream's first three lines (`oauth_user_needs_password_reset?`, `skip_confirmation!`, `set_random_password_if_oauth_user`) and replaces only the redirect. It overrides that method for every provider, enterprise's `saml` included. |
| `app/views/devise_overrides/omniauth_callbacks/mobile_handoff.html.erb` | `f39a83ee62` | **Deleted** (it was Comvor-only). It now lives at `custom/app/views/comvor/mobile_handoff.html.erb`, with keys `comvor.mobile_handoff.*`. | Nothing to do. |
| `app/models/concerns/sso_authenticatable.rb` | `50550bd640` | **Upstream.** `generate_mobile_sso_deep_link` moved to `Custom::Concerns::User`. Its spec moved to `spec/custom/models/user_mobile_sso_deep_link_spec.rb`. | Take upstream's. The link reuses upstream's `generate_sso_auth_token`. The email in it is encoded twice on purpose, a shape verified on a real device: don't "fix" it. |
| `config/routes.rb` (was `:550-562`) | `c3e3d0fb6a`, `7dd234c9e2`, `4a443fc8bd` | **Upstream for SAML.** Moved to `comvor_routes.rb`. | Take upstream's. (The bot routes in 3b are a separate edit.) |
| `config/initializers/rack_attack.rb` | `4acd6bb0eb` | **Upstream.** Moved to `comvor_rack_attack.rb`. | Take upstream's. |
| `config/initializers/comvor_saml_idp_pin.rb`, `lib/comvor/portal_idp.rb`, `lib/comvor/saml_idp_pin.rb` | hotfix `9e3526bc51` | **Deleted.** Moved to `custom/config/initializers/` and `custom/lib/comvor/`. | Nothing to do. |
| `app/controllers/dashboard_controller.rb:92` (`allowed_login_methods`) | `c7ac1411ed` | **Upstream.** Replaced by the hook in section 2. | Take upstream's. |
| `app/controllers/api/v1/profiles_controller.rb` | `c79b8f1808` | **Upstream** apart from the hook line. | Take upstream's. |
| `app/models/user.rb:68` `omniauth_providers: [:google_oauth2, :saml]` | upstream | **Untouched.** Devise does not need `:comvor_saml` listed: the request specs sign in on the web and on mobile without it (spec R2-2). | Take upstream's. |
| `config/locales/en.yml` | `c79b8f1808`, `f39a83ee62`, `d67ca71353` | **Upstream.** The override of `messages.reset_password_saml_user` and the hand-off strings moved to `custom/config/locales/en.yml`. The unused key `messages.login_portal_totp_user` was dropped. | Take upstream's. If upstream renames `messages.reset_password_saml_user`, rename our override, or the refusal shows upstream's text. `spec/custom/requests/comvor_saml_passwords_spec.rb` pins the text. |
| `config/initializers/sentry.rb:1-23, :38-67` | `55242e4689`; comment `0578087949` | **Still edited.** It scrubs `X-Comvor-Portal-Secret`, `api-access-token` and `authorization` headers, and every cookie, from Sentry events (`before_send`). | Keep ours, and re-apply it if upstream rewrites `Sentry.init`. It cannot move: custom initializers run before `config/initializers`, so `Sentry.init` has not run yet. This is a security edit. |
| `app/javascript/v3/views/login/Index.vue:315-323` | `879f2040a4` | **Still edited.** "Forgot password" is a plain link to `https://app.comvor.com/forgot-password`, not the router link to `auth/reset/password`. | Keep ours. The frontend has no extension point. |
| `app/javascript/dashboard/routes/dashboard/settings/profile/ChangePassword.vue:4, :49-55, :91, :150-152` | `879f2040a4` | **Still edited.** It hides the password form for `provider === 'saml'` and shows `PROFILE_SETTINGS.FORM.PASSWORD_SECTION.SAML_MANAGED_NOTE` (`i18n/locale/en/settings.json:83`). | Keep ours, and keep the en.json key. |
| `app/javascript/dashboard/api/auth.js:22-26` and `dashboard/store/utils/api.js:79-91` | `cd1c376639` | **Still edited.** Logout follows `saml_logout_url` from the sign-out response, through `clearCookiesOnLogout(redirectLink)`. | Keep both. The server contract (`saml_logout_url` in the `DELETE /auth/sign_out` body) is `Custom::DeviseOverrides::SessionsController`'s. |
| `app/javascript/v3/helpers/RouteHelper.js:48` and `specs/RouteHelper.spec.js` | `c07bd90983` | The hook line from section 2. | See section 2. |

### 3b. Other Comvor work in upstream files (outside the off-enterprise move)

These edits predate this work and are not about `enterprise/`. The rule for all of them: keep ours, and re-apply any hunk upstream rewrites. `git diff 00837019b5 HEAD -- <path>` shows each one. Moving them into `custom/` is future work.

- **Branding.** Commits `ac67001efb`, `7c3fd419ed`, `5ba9d18b9f`, `d5d1064129`, `df2181e8d6`.
  - `public/` icons and brand assets (`manifest.json` and `browserconfig.xml` included), `theme/colors.js`, the administrate `_variables.scss` files, and `_next-colors.scss`.
  - `Logo.vue`, `AudioRecorder.vue`, `EmojiInput.vue`, `useBranding.js` and `shared/helpers/branding.js` (with its spec), `entrypoints/{dashboard,v3app}.js`.
  - The en.json strings `login`, `resetPassword` and `signup`.
  - `layouts/vueapp.html.erb`, `installation/onboarding/index.html.erb`, `integrations/app.rb`, `config/installation_config.yml`, `config/schedule.yml`, `lib/chatwoot_hub.rb` (phone-home off: CE baseline `spec/lib/chatwoot_hub_spec.rb:18`/`:26`).
- **Sidebar link and settings.** Commits `9f7b88547e` and `7a5cf47747`.
  - `Sidebar.vue`, `SidebarComvorLink.vue` (with its spec), `settings.json` `COMVOR_DASHBOARD`.
  - `dashboard_controller.rb:80-81`: `WHATSAPP_API_VERSION` (`a41b1eab66`) and `COMVOR_ENGINE_URL`, the latter read nowhere in `app/javascript` today.
- **Retail reliability and bot API.** Commits `b08f9b4f99`, `e7ea871d6e`, `cc088f457f`, `2db2af1eb6`, `597f950ed2`, `26800cbad3`, `b234fd60d9`, `3520c75ab8`, `8921a9351a`, `f7e35e69e8`.
  - Code: `messages_controller.rb`, `message_builder.rb`, `reply_eligibilities_controller.rb`, `delivery_profiles_controller.rb`, `access_token_auth_helper.rb`, `message.rb`, `conversation.rb`, `event_data_presenter.rb`, `message_window_service.rb`, `whatsapp/approved_templates_summary_service.rb`, `_message.json.jbuilder`.
  - Config, schema and docs: `config/routes.rb` (`reply_eligibility`, `delivery_profile`), three `db/migrate/20260916*` migrations, `db/schema.rb`, `swagger/**`.
  - Their specs under `spec/controllers`, `spec/models`, `spec/listeners`, `spec/presenters` and `spec/services`.
- **Workspace seat cap and inbox membership.** Commits `98ca237b6f` and `579cdc61f9`. `account.rb`, `account_user.rb`, `inbox.rb`, `inbox_member.rb`, `AddAgents.vue` (with its spec), `lib/tasks/ops/comvor_backfill_inbox_members.rake`, and specs `agents_seat_limit_spec.rb`, `comvor_auto_inbox_membership_spec.rb` and `account_spec.rb`.
- **Channels.**
  - Facebook: `a9fe00882a`, `0b71b727f5`, `795fd9ff12`.
  - Instagram: `856a21d019`.
  - Widget: `54ffaa04e6`, `c4fc0c9ad1`.
  - Files: `facebook/message_builder.rb`, `send_on_facebook_service.rb`, `human_agent_tag_helpers.rb`, `instagram/*send*`, `Facebook.vue`, `Reauthorize.vue`, `widget/store/modules/agent.js`, `widget/inbox_members/index.json.jbuilder`, and their specs.
  - **WhatsApp Embedded Signup v4 and coexistence.** A port of upstream `79e145bc20` (#15462, not in the fork's base) in its own names: `is_coexistence`, `classifySignupEvent`, `SIGNUP_RESULT`, `setup_webhooks(is_coexistence:)`, `should_register_phone_number?`, `expected_phone_number:`, `ReauthorizationService(waba_id:)`, i18n `UNSUPPORTED_COMPLETION`. Files: `whatsapp/utils.js`, `WhatsappEmbeddedSignup.vue`, `whatsapp/Reauthorize.vue`, `inboxMgmt.json`, `authorizations_controller.rb`, `channel/whatsapp.rb`, and `embedded_signup`, `webhook_setup`, `phone_info`, `health` and `reauthorization` services, with their specs. **Merge rule: take upstream's, then re-apply two Comvor lines** if upstream still lacks them: `version: 'v4'` in the FB.login extras (`EMBEDDED_SIGNUP_EXTRAS` in `utils.js`, pinned in `whatsapp/specs/utils.spec.js`), and `classifySignupEvent` reading `data.data.error_message` (Meta's v4 ERROR puts the message inside `data`). Keep `whatsapp/specs/utils.spec.js` and `channels/specs/WhatsappEmbeddedSignup.spec.js`; adapt them if upstream's composable replaces the component logic.
- **Ops and docs.** `.github/workflows/deploy.yml` (CD), `docker/Dockerfile` (`1bd059d24e`), `AGENTS.md`, `.gitignore`, and Comvor's own design notes under `docs/superpowers/`.
- **Upstream fixes the fork took after `00837019b5`.** These are not Comvor's: `articles_controller.rb`, `article.rb`, `FullEditor.vue`, `PortalsArticlesNewPage.vue`, and the instagram send services in part. Take upstream's.

## 4. Verifiers and the baseline (run after every merge)

Comvor's scripts, not upstream files:
- `bin/comvor-test-db`
- `bin/e-check`
- `bin/ce-check`
- `bin/spec-baseline`
- `custom/spec_baseline.yml`

Run each with rbenv initialised (`eval "$(rbenv init -)"`).

- **`bin/comvor-test-db`.** Sourced by both checks. It points the specs at `chatwoot_off_enterprise_test` (override it with `COMVOR_TEST_DATABASE`; the name must end in `_test`), never at the dev database that `.env` names. It creates and loads that database only when it is missing.
  - For an ad-hoc run: `( eval "$(rbenv init -)"; source bin/comvor-test-db && comvor_test_db_ready && bundle exec rspec <files> )`.
- **`bin/e-check [files]`.** E mode: the working tree as it is, with enterprise present. With no arguments it runs `spec/custom` plus every file in the `e:` baseline.
- **`bin/ce-check [files]`.** CE mode: a throwaway worktree of **HEAD** (commit first), with `enterprise/` and `spec/enterprise/` deleted, the way upstream's `.github/workflows/run_foss_spec.yml` does it. With no arguments it runs `spec/custom` plus the `ce:` baseline files.
- **`bin/spec-baseline <ce|e> results.json status`.** Judges a JSON run against `custom/spec_baseline.yml`. A check passes only when:
  - every failure is listed for that mode;
  - no listed example passed (a stale entry fails the check);
  - every entry is well-formed;
  - rspec did not abort.
- **Baseline entries.** Each entry is `file:line`, with either `superseded_by:` (the `spec/custom` example that replaces an upstream example Comvor's prepended code now answers) or `preexisting: true` plus `base:`.
  - After a merge, upstream line numbers in `spec/enterprise` shift. Fix the `example:` lines from the check's NEW FAILURE / STALE output.
  - If a `spec/custom` file shifts, fix the `superseded_by:` lines too.
- **Both checks share the test database.** They refuse to start while any rspec is running. Never run two at once.
- **After a merge, also run** the full E-mode suite, `bundle exec rspec spec` under `bin/comvor-test-db`, in the background. Compare its failure set (`--format json --out <file>`) with the same run on the pre-merge commit.
- **And check that `enterprise/` is clean:** `git diff --stat <upstream-commit> HEAD -- enterprise spec/enterprise` must print nothing.

## 5. Unsupported

- **`DISABLE_ENTERPRISE=true` with `custom/` present.** It is a third mode nobody tests, and `extensions` then still lists `enterprise` when the folder exists. Prod never sets it.
  - "Off enterprise" means the folder is deleted (CE mode), which is what `bin/ce-check` and `run_foss_spec.yml` test.

## 6. Accepted risks and deliberate differences from upstream (and from the pre-move fork)

- **No unique index on `account_saml_settings.account_id`.** That table is upstream's, and an index would make `db/schema.rb` drift from upstream on every merge. A second POST gets 422 (an app-level check), and the only writer is comvor-api, one account at a time.
- **Super Admin "Chatwoot edition" reads "Custom" in CE.** `custom?` is true there. This is cosmetic.
- **The SAML request phase does not check the account's `saml` feature, by design.** It answers alike with or without a settings row, so it does not reveal which accounts use SSO. The callback still checks it, and the kill switch covers both phases.
- **A reset request for a `saml` email answers 200, like any other email.** It sends no token; instead it mails a pointer to the portal's reset page (`Comvor::SamlPasswordPointerMailer`). Upstream answers 403. This is baselined in `e:`.
- **The kill switch `ENABLE_SAML_SSO_LOGIN` is strict: only `'true'` switches SAML on.** `false`, `FALSE` and `0` switch it off everywhere. Prod is `true`.
- **A takeover assigns the replier, and skips round robin.** It assigns the replying agent when they are assignable, and otherwise leaves the conversation unassigned. The inbox's round robin no longer runs on a takeover (spec H).
- **A merchant reply from the WhatsApp Business phone app does not take over.** The sender is nil (an external echo), which cannot be told apart from the bot's own photo echo.
- **Logout CSRF through GET** on the workspace sign-out is kept as it was. It only ends the caller's own session.
- **Login CSRF without `InResponseTo` binding.** The portal can sign a portal user into their own Chatwoot session unasked. This is a known trade-off.
- **Timing differences are accepted:** member vs unknown email on SAML sign-in, and portal round trips on password delegation. Bodies and statuses match.
- **Rails internals in the takeover.** `Custom::Message` overrides `trigger_transactional_callbacks?` and calls `_run_commit_callbacks`, both verified on activerecord 7.1.5.2.
  - Re-run `spec/custom/models/message_takeover*` and `spec/custom/requests/comvor_takeover_spec.rb` on every Rails upgrade.
- **A ruby-saml private method.** The replay TTL reads the signed SubjectConfirmationData through `xpath_from_signed_assertion` (`send`), pinned at ruby-saml 1.18.1 in `Gemfile.lock`. A strategy spec guards it; re-check it on a ruby-saml upgrade.
- **`custom/lib/omni_auth` is excluded from Zeitwerk.** The strategy is required by `comvor_saml.rb`, because middleware is built once at boot.
- **`FRONTEND_URL` must equal comvor-api's `chatwootPublicURL` byte for byte**, trailing slash included. The SAML Destination is compared byte-equal against the ACS.
- **The push-flag list exists once,** as `Custom::AccountUser::INBOX_MEMBER_PUSH_FLAGS`; `Comvor::SamlUserBuilder::NEW_MEMBER_PUSH_FLAGS` is the same constant. The builder sets the flags itself because auto inbox membership may be off.
- **Super Admin can still set a `saml` user's password** (`app/dashboards/user_dashboard.rb`, operator only). It is left as upstream has it: `Custom::DeviseOverrides::SessionsController` never accepts a `saml` user's local password, so a password set there cannot sign anyone in.
- **`users.provider` is per user, not per account.** A member of two accounts becomes `saml` at their first SSO sign-in to either, and from then on signs in through the portal for both (upstream behaves the same). `Comvor::SamlProviderResetJob` only puts them back when no account they belong to has SSO configured.
- **The settings pin hashes the first certificate the portal publishes** (`Comvor::PortalIdp.certificate_sha256`), while sign-in accepts any listed one. During a portal key rotation, a row provisioned with the second certificate is refused until the first is retired; sign-in is unaffected.

### Accepted losses once `enterprise/` is gone (phase 3)

- Audit rows stop.
- `IS_ENTERPRISE` becomes false, which hides Copilot and the per-inbox assignment limit.
- SLA, custom roles, capacity, Captain and the enterprise webhooks go (0 rows on prod).
- Agents added in Chatwoot stay `provider='email'`.
- Unverified: whether the official mobile app gates its SSO button on `IS_ENTERPRISE`.

## 7. Phase-2 deploy prerequisites (enterprise still in the image)

1. **Deploy comvor-api first,** with both return addresses (the dual-ACS change). Then deploy the fork. To roll back, revert the fork merge; comvor-api kept accepting both addresses (historical: since 2026-11-06 it lists only `comvor_saml`'s).
2. **Set `COMVOR_PORTAL_URL=https://app.comvor.com`** in `comvor-deploy/config/deploy.chatwoot.yml`. The `saml` reset pointer mail and an absolute sign-out `return_to` need it.
3. **Check where comvor-api's `POST /internal/portal/agent_session` arrives from.** If it is loopback or an address in `RACK_ATTACK_ALLOWED_IPS`, upstream's safelist skips both Comvor throttles.

## 8. Phase 3 (`enterprise/` out of the image)

1. **Before the deploy,** check Sidekiq (Super Admin, Sidekiq page) for queued, scheduled or retrying jobs from `enterprise/app/jobs`: the `Captain::`, `Sla::`, `Enterprise::`, `Migration::` and `Portal::ArticleIndexingJob` classes, `Messages::AudioTranscriptionJob`, `Internal::AccountAnalysisJob` and `Saml::UpdateAccountUsersProviderJob`. After the deploy they cannot load and will end up in the dead set.
2. **The `.dockerignore` lines** ship with this phase. To roll back, drop them and redeploy. Since the cleanup below, a rollback brings enterprise's `/omniauth/saml/callback` back **without `ComvorSamlCallbackGuard`**. comvor-api no longer mints for that address, but the strategy trusts whatever `sso_url` and certificate each stored row holds, and the settings pin only checks writes. So a rollback is safe only while every `account_saml_settings` row names the portal. **Before rolling back,** run the read-only check: every row's `sso_url` and `idp_entity_id` are the portal's, `sp_entity_id` is `comvor-chatwoot-account-<account_id>`, and the certificate is the one `/portal/saml/metadata` publishes. Checked 2026-11-06: 7 of 7 rows pass, one certificate, equal to the published one.
3. **The mobile app is unaffected.** The official app (read at `2f3ff09`, 2026-11-03) never reads `IS_ENTERPRISE`. It shows its own SSO button only when the server address contains `app.chatwoot.com`, so on our host the portal deep link has always been the only SSO path.
4. **Done 2026-11-06:** comvor-api lists only `/omniauth/comvor_saml/callback` (`internal/portal/samlidp/sp.go`); `ComvorSamlCallbackGuard`, `Comvor::PortalIdp.pinned?` and the phase-2 coexistence spec are gone. Deploy order does not matter: neither side uses the old path since phase 3.
