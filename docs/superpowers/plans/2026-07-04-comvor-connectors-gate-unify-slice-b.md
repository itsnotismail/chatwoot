# Comvor Connectors — Gate + Unify (Slice B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop offering the untested `shopify` connector to merchants, and collapse the two overlapping connector sections into one coherent panel whose "connect" action also enables the connector at runtime.

**Architecture:** Two repos. **comvor-engine** (`dev` branch, Go): add a GA/readiness gate so only production-ready connectors are offered on the merchant-facing surfaces. **seytu-cw** (`seytu` branch, Vue): unify the connector tab, make the connector list data-driven from the GA surface, and wire "connect Ewity" to also enable it in `account_connectors` (the table the runtime resolves capabilities from — [turnscope.go:33](comvor-engine/internal/orchestrator/turnscope.go)).

**Tech Stack:** Go 1.26 + testcontainers (comvor-engine); Vue 3 `<script setup>`, Tailwind, vitest (seytu-cw).

## Global Constraints

- comvor-engine branch **`dev`** (NEVER `prod`); seytu-cw branch **`seytu`** (NEVER `seytu-prod`).
- **seytu-cw node v22**: prefix every `pnpm`/`vitest`/`eslint`/`git commit` with `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH`.
- **comvor-engine store/API tests need Docker** (testcontainers). Run `go test ./...` from the repo root; use `git -C ~/Sites/my-agent/comvor-engine`.
- Keep `internal/flow` pure; `internal/api` must not import `internal/orchestrator`.
- `shopify` stays **registered** (its capability declarations + characterization tests remain) — it is only hidden from what merchants are *offered*.
- i18n additions: `en.json` only, sentence case, plain language.

---

### Task 1: Backend GA/readiness gate

**Problem:** `shopify` and `ewity` are both registered as retail-compatible ([main.go:266](comvor-engine/cmd/server/main.go:266), `:276`), so `CompatibleConnectors("retail")` returns both and `shopify` leaks into the `/connectors` `available` list and the merchant-facing surfaces — despite being untested and having no credential UI.

**Fix:** add a `ready` flag to registration; add `Registry.AvailableConnectors(category)` returning `compatible ∩ ready`; point the four merchant-facing call sites at it. Mark `shopify` not-ready, `ewity` and `none` ready.

**Files:**
- Modify: `internal/connectors/connector.go` (`Register` signature + `readiness` map + `AvailableConnectors`)
- Modify: `cmd/server/main.go` (registration calls — add readiness arg)
- Modify: `internal/api/connectors_handler.go` (lines ~96, ~201 — use `AvailableConnectors`), `internal/api/account_handler.go` (line ~259), `internal/api/verticals_handler.go` (compatible_connectors field), and the `ConnectorCompatibilityLister` interface(s) exposing these methods
- Modify: `internal/connectors/connector_test.go` (registration calls) and add new coverage

**Interfaces:**
- Produces: `Registry.AvailableConnectors(category string) []string` — compatible connectors that are also GA-ready. `Registry.CompatibleConnectors` stays unchanged (still returns all registered-compatible; used by runtime `Lookup` validation and any non-merchant path).
- The api-side interface currently named for `CompatibleConnectors` gains `AvailableConnectors(category string) []string`.

- [ ] **Step 1: Write the failing test**

In `internal/connectors/connector_test.go`, add `TestRegistry_AvailableConnectors_ExcludesNotReady`: register `ewity` (retail, ready=true), `shopify` (retail, ready=false), `none` (`*`, ready=true). Assert `AvailableConnectors("retail")` contains `ewity` and `none` but NOT `shopify`; assert `CompatibleConnectors("retail")` still contains all three.

- [ ] **Step 2: Run it to confirm it fails**

Run: `git -C ~/Sites/my-agent/comvor-engine test ./internal/connectors/ -run AvailableConnectors` (i.e. `cd ~/Sites/my-agent/comvor-engine && go test ./internal/connectors/ -run AvailableConnectors`)
Expected: FAIL — method/param don't exist (compile error).

- [ ] **Step 3: Implement registry readiness**

In `connector.go`: change `Register(connectorType string, categories []string, ready bool, factory Factory)`; store `r.ready[connectorType] = ready`. Add:

```go
// AvailableConnectors returns the compatible connectors for a category that
// are also production-ready (GA). Merchant-facing surfaces (config API,
// verticals, account connector_type validation) offer only these; the full
// CompatibleConnectors set is still used for runtime type validation.
func (r *Registry) AvailableConnectors(category string) []string {
	out := []string{}
	for _, c := range r.CompatibleConnectors(category) {
		if r.ready[c] {
			out = append(out, c)
		}
	}
	return out
}
```

Initialize the `ready` map in `NewRegistry`.

- [ ] **Step 4: Update registrations + call sites**

- `cmd/server/main.go`: `registry.Register("none", []string{"*"}, true, ...)`, `registry.Register("shopify", []string{"retail"}, false, ...)`, `registry.Register("ewity", []string{"retail"}, true, ...)`.
- Add `AvailableConnectors(category string) []string` to the api interface(s) that declare `CompatibleConnectors` (search: `CompatibleConnectors(category string) []string` in `internal/api`).
- Switch merchant-facing sites to `AvailableConnectors`: `connectors_handler.go` line ~96 (enable-PUT compatibility check) and ~201 (available GET loop); `account_handler.go` line ~259 (connector_type validation); `verticals_handler.go` (the `compatible_connectors` response field).
- Update every `Register(` call in `connector_test.go` to the new signature (ready=true for existing stubs unless a test needs otherwise).

- [ ] **Step 5: Add an API-level test**

Extend the connectors handler test (or add one) asserting the `/connectors` `available` list for a retail account excludes `shopify` and includes `ewity`.

- [ ] **Step 6: Run the suite**

Run: `cd ~/Sites/my-agent/comvor-engine && go test ./... -race`
Expected: PASS.

- [ ] **Step 7: Commit**

Commit: `feat(connectors): gate non-GA connectors out of merchant-facing surfaces`

---

### Task 2: Unify the connector tab (data-driven + connect-to-enable + fold the enable-list)

**Problem:** the connector tab has two overlapping sections — a legacy single-connector editor (top, Ewity-specific creds/permissions/test, hard-coded `None`/`Ewity` options) and the multi-connector enable-list (bottom, `account_connectors`). To add/manage connectors there's no coherent flow, and the bottom list exposed `shopify` with no way to credential it. Critically, the runtime reads `account_connectors.ListEnabled` — so enabling must survive the consolidation.

**Design (agreed "gate + unify"):** one Connector panel. The connector-type `<select>` is **data-driven** from the GA list (so it never drifts from the enable surface again). Saving/connecting Ewity **also enables `ewity` in `account_connectors`**; selecting `None` disconnects (disables it). Remove the standalone bottom enable-list; the provider-on-conflict UI is deferred (no effect with one connector) and the soft-wall capability toggles move into a collapsed "Advanced" section rendered only when relevant.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/settings/comvor/Index.vue` (connector tab template ~1171–1360 and the connector script: `saveConnector`, `connectorType`, `compatibleConnectors`, `onConnectorsUpdate`, `saveConnectors`, `loadConnectors`)
- Modify: `discovery/ConnectorsEditor.vue` (keep only the soft-wall capability toggles + provider-conflict select; drop the connector enable-checkbox list — it moves to the unified panel's connect action) — OR retire it and inline the Advanced section. Implementer's choice; keep behavior.
- i18n: connector-type option labels, "Connected"/"Not connected" status, "Advanced" toggle
- Test: `app/javascript/dashboard/routes/dashboard/settings/comvor/specs/` — add/extend a `ConnectorTab.spec.js`

**Interfaces:**
- Consumes: Task 1's GA-gated `/connectors` `available` and `/verticals` `compatible_connectors`.
- Produces: the connector panel renders type options from the GA list; `saveConnector` for `ewity` issues (a) the existing `/accounts` + `/connectors/ewity` writes AND (b) a `PUT /connectors` merging `ewity` into `enabled`; selecting `None` + save issues `PUT /connectors` with `ewity` removed from `enabled`.

- [ ] **Step 1: Read the current tab**

Read `Index.vue` lines 1171–1360 (connector tab template) and the connector-related script (lines ~27–230, ~340–535) to learn the exact refs (`connectorType`, `ewityToken`, `ewityPermissions`, `connectors`, `saveConnector`, `saveConnectors`) before editing.

- [ ] **Step 2: Write the failing tests**

In `specs/ConnectorTab.spec.js` (create), mount `Index.vue` (or extract the connector tab if mounting the whole page is impractical — if so, note it and test the smallest mountable unit) with stubbed `fetch`:
- The connector-type `<select>` renders one option per GA connector returned by `/verticals` `compatible_connectors` (e.g. `none`, `ewity`) — assert it is driven by data, not hard-coded (feed a list of just `['none','ewity']` and assert two options; there must be no `shopify` option ever).
- After setting type `ewity` + a token and calling `saveConnector`, assert a `PUT` to `/api/accounts/:id/connectors` was made whose body `enabled` includes `'ewity'`.
- After setting type `none` and calling `saveConnector`, assert the `PUT /connectors` body `enabled` does NOT include `'ewity'`.

- [ ] **Step 3: Run tests to confirm they fail**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- comvor/specs/ConnectorTab.spec.js`
Expected: FAIL.

- [ ] **Step 4: Data-drive the connector-type select**

Replace the hard-coded `None`/`Ewity POS` `<option>` markup with a `v-for` over `compatibleConnectors` (already computed from `activeVertical.compatible_connectors`), using a small label map:

```js
const CONNECTOR_TYPE_LABELS = {
  none: 'COMVOR_SETTINGS.CONNECTOR.TYPE_NONE',
  ewity: 'COMVOR_SETTINGS.CONNECTOR.TYPE_EWITY',
};
```

Render `<option v-for="c in compatibleConnectors" :key="c" :value="c">{{ t(CONNECTOR_TYPE_LABELS[c] || c) }}</option>`. (Because Task 1 GA-gates the list, `shopify` can never appear here.)

- [ ] **Step 5: Wire connect-to-enable in saveConnector**

After the existing Ewity creds save succeeds, reconcile `account_connectors`:

```js
async function syncConnectorEnabled() {
  const enabled = new Set(connectors.value?.enabled || []);
  if (connectorType.value === 'ewity') enabled.add('ewity');
  else enabled.delete('ewity');
  const res = await fetch(`${engineURL()}/api/accounts/${accountId}/connectors`, {
    method: 'PUT',
    headers: authHeaders(),
    body: JSON.stringify({
      enabled: [...enabled],
      providers: connectors.value?.providers || {},
      disabled_capabilities: connectors.value?.disabled_capabilities || [],
    }),
  });
  if (!res.ok) throw new Error(await res.text());
}
```

Call `await syncConnectorEnabled()` inside `saveConnector` after the creds PUT, before the success alert; then `await loadConnectors()`. Ensure `authHeaders`/`engineURL` are the ones already defined in the component.

- [ ] **Step 6: Fold the enable-list**

Remove the standalone bottom "Connectors" enable-list section (`<ConnectorsEditor>` block + its "Save Connectors" button) from the connector tab, since connect/disconnect now happens through the unified panel. Preserve the **soft-wall capability toggles**: render them (from the existing `disabledCapabilities`/`softWarnings` logic) inside a collapsed **"Advanced"** `<details>`/toggle in the unified panel, shown only when `toggleableCapabilities.length`. Keep `saveConnectors`/`onConnectorsUpdate` wiring for that Advanced section, or merge its save into the unified Save. Remove the now-dead provider-conflict `<select>` from the visible flow (one GA connector ⇒ never triggered); keep the code path dormant.

- [ ] **Step 7: Run tests to verify they pass**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- comvor/specs/`
Expected: PASS. Update any existing ConnectorsEditor specs that assumed the standalone enable-list.

- [ ] **Step 8: Lint + commit**

Commit: `feat(comvor): unify the connector panel and enable on connect`

---

### Task 3: Accurate dirty tracking (Connectors)

**Problem:** `connectorsDirty` in `Index.vue` ([Index.vue:195](seytu-cw/app/javascript/dashboard/routes/dashboard/settings/comvor/Index.vue:195)) is a one-way latch — reverting a connector edit leaves "unsaved changes" showing. Same fix pattern as Slice A Task 2.

**Files:**
- Modify: `Index.vue` (connector-tab dirty state)
- Test: `comvor/specs/ConnectorTab.spec.js`

- [ ] **Step 1: Write the failing test**

After load, assert connector dirty is `false`; change a connector field to a new value → `true`; set it back to the loaded value → `false`.

- [ ] **Step 2: Run it to confirm it fails**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- comvor/specs/ConnectorTab.spec.js`
Expected: FAIL — dirty stays true after revert.

- [ ] **Step 3: Implement baseline snapshot**

Add `serializeConnectorForm()` projecting the editable connector state (`connectorType`, `ewityToken` only if user-typed, `ewityPermissions`, `connectors.enabled`/`providers`/`disabled_capabilities`) to a JSON string; capture `connectorBaseline` on load/after save; replace the `connectorsDirty` latch (and any separate connector-form dirty) with a computed `=== baseline` comparison. Mirror Slice A Task 2 exactly.

- [ ] **Step 4: Run tests to verify they pass**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- comvor/specs/ConnectorTab.spec.js`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

Commit: `fix(comvor): clear connector unsaved-changes flag on revert`

---

### Task 4: Slice verification

- [ ] **Step 1:** comvor-engine: `cd ~/Sites/my-agent/comvor-engine && go test ./... -race` — PASS; confirm coverage not regressed.
- [ ] **Step 2:** seytu-cw: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- app/javascript/dashboard/routes/dashboard/settings/comvor/` — PASS.
- [ ] **Step 3:** Lint touched seytu-cw files.
- [ ] **Step 4:** Manual sanity note in the PR/handoff: connecting Ewity through the unified panel enables it in `account_connectors` (verify capabilities resolve); `shopify` no longer appears anywhere in the connector tab.
- [ ] **Step 5:** Commit any fixes: `chore(comvor): slice B verification`
