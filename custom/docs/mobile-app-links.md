# Mobile app links during the move to Comvor Agent

Both apps take the one-time SSO hand-off until the official Chatwoot app is retired. Code: `custom/lib/comvor/mobile_app.rb`, `custom/lib/comvor/android_asset_links.rb`.

## Which app a hand-off opens

| Request | Link scheme |
|---|---|
| no app (today's callers) | `MOBILE_DEEP_LINK_BASE`, default `chatwootapp` |
| `POST /internal/portal/agent_session` with `app: "comvor"` | `comvor://` (Comvor Agent) |
| same with `app: "chatwoot"` | `chatwootapp://` (official app), whatever `MOBILE_DEEP_LINK_BASE` says |
| same with any other `app` | 400 `unknown app` |
| SSO page `/app/login/sso?target=mobile` (RelayState `mobile`) | default scheme |
| SSO page `/app/login/sso?target=mobile_comvor` (RelayState `mobile_comvor`) | `comvor://`, success and refusal alike |

The link is otherwise unchanged: the email in it is still encoded twice (`a%2540x.com`), the shape proven on a real device. Do not "fix" it.

comvor-api forwards `?app=` from the portal's `POST /portal/api/v1/workspace/mobile-link`; the portal chooses the buttons with `NEXT_PUBLIC_MOBILE_APPS` (`chatwoot` default, `both`, `comvor`). Promote fork, then comvor-api, then the portal: the portal hides a Comvor Agent button whose link is not `comvor://`, so an older api is safe, but an older fork answers `app` with its default scheme.

## Android App Links (`/.well-known/assetlinks.json`)

| Env | Meaning |
|---|---|
| `ANDROID_BUNDLE_ID`, `ANDROID_SHA256_CERT_FINGERPRINT` | upstream's single statement, unchanged (the official app) |
| `COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS` | comma-separated SHA-256 fingerprints for `com.comvor.agent`: upload key, Play App Signing key (exists only after the Play app is created), optionally a debug key. Unset or no valid value: no Comvor Agent statement. Values that are not `AA:BB:...` (32 bytes) are dropped. |

Fingerprints are public, not secrets. Print one with `keytool -list -v -keystore <keystore>` (SHA256 line) or copy it from Play Console > App integrity. Verify on a device with `adb shell pm get-app-links com.comvor.agent` (wants `verified` for `chat.comvor.com`); verification needs the file on a public HTTPS host.
