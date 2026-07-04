# Comvor UI Polish — Slice A (Discovery + Notifications) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the discovery/notifications editor UX gaps a merchant hit in testing — a dead-feeling journey strip, non-functional `?` help markers, a bloated + duplicative notification-enabling model, and a sticky "unsaved changes" flag.

**Architecture:** All changes are in the **seytu-cw** repo (Chatwoot fork), Vue 3 `<script setup>`, under `app/javascript/dashboard/routes/dashboard/settings/comvor/`. No backend (comvor-engine) changes in this slice — the notifications-routing rework writes stage `notify_enabled`/`notify_guidance` through the **existing** `PUT /flow-config` endpoint and routing through the existing `PUT /notifications` endpoint.

**Tech Stack:** Vue 3 Composition API, Tailwind (utility classes only), vue-i18n (`en.json`), vitest + @vue/test-utils, lodash (`isEqual` available via `lodash/isEqual`).

## Global Constraints

- Branch: **`seytu`** (NEVER `seytu-prod`).
- **node v22 toolchain**: prefix EVERY `pnpm` / `vitest` / `eslint` / `git commit` command with `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH`. Lint with `pnpm exec eslint <files>` (the `pnpm eslint` script ignores path args).
- Vue components: PascalCase; events: camelCase; `<script setup>` at top.
- **Tailwind only** — no custom/scoped CSS, no inline styles.
- **i18n**: no bare strings in templates; add keys to `app/javascript/dashboard/i18n/locale/en/*.json` (only `en`). All new user copy is **sentence case**, plain-language (no jargon like "cutoff", "capability").
- Native `<button>`/`<input>`/`<select>` elements (no `woot-button`).
- Run specs after each task: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- <spec path>`.
- Commit after each task (Conventional Commits, no "Claude" reference).

---

### Task 1: Journey strip reactivity fix — edits reflect before save

**Problem:** `onStageUpdate` buffers changes into `draftStages` but never mutates `flowConfig`, which is what the editor renders from. So clicking a journey pill (or any derived-state control) does nothing visible until Save Draft reloads.

**Files:**
- Modify: `app/javascript/dashboard/routes/dashboard/settings/comvor/discovery/DiscoveryFlowTab.vue` (`onStageUpdate`, ~line 118)
- Test: `app/javascript/dashboard/routes/dashboard/settings/comvor/discovery/specs/DiscoveryFlowTab.spec.js` (create or extend)

**Interfaces:**
- Consumes: `flowConfig` is a `ref` over the parsed `/flow-config` JSON; `flowConfig.value.flows[].stages[]` are deeply reactive.
- Produces: after `onStageUpdate`, the matching stage object in `flowConfig.value` carries the updated fields, so `SalesFlowEditor`'s `cutoffKey`/`botStages`/`teamStages` recompute live.

- [ ] **Step 1: Write the failing test**

In the spec, mount `DiscoveryFlowTab` with a stubbed `fetch` returning a flow-config whose `ordered` flow has stages `[{stage_key:'discovery',on_complete:'continue'},{stage_key:'order',on_complete:'handoff'}]`. Call the exposed `onStageUpdate` (via `wrapper.vm` / `defineExpose`) with `{flow_key:'sales', stage_key:'discovery', on_complete:'handoff'}` and assert `wrapper.vm.flowConfig.flows.find(f=>f.mode==='ordered').stages.find(s=>s.stage_key==='discovery').on_complete === 'handoff'`.

Add `onStageUpdate` to the component's `defineExpose` if not already present (it is not — add it).

- [ ] **Step 2: Run test to verify it fails**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/DiscoveryFlowTab.spec.js`
Expected: FAIL — `discovery` stage `on_complete` is still `continue`.

- [ ] **Step 3: Implement — optimistically apply the update to flowConfig**

Replace `onStageUpdate` body:

```js
function onStageUpdate(update) {
  const key = `${update.flow_key}:${update.stage_key}`;
  draftStages.value = {
    ...draftStages.value,
    [key]: { ...draftStages.value[key], ...update },
  };
  // Optimistically reflect the edit in the rendered config so derived UI
  // (cutoff zones, the handoff marker, who-completes) updates immediately
  // instead of only after a save+reload.
  const flow = (flowConfig.value?.flows || []).find(
    f => f.flow_key === update.flow_key
  );
  const stage = flow?.stages?.find(s => s.stage_key === update.stage_key);
  if (stage) {
    const { flow_key: _fk, stage_key: _sk, ...fields } = update;
    Object.assign(stage, fields);
  }
  flowDirty.value = true;
}
```

Add `onStageUpdate` to `defineExpose`.

- [ ] **Step 4: Run test to verify it passes**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/DiscoveryFlowTab.spec.js`
Expected: PASS.

- [ ] **Step 5: Lint + commit**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm exec eslint app/javascript/dashboard/routes/dashboard/settings/comvor/discovery/DiscoveryFlowTab.vue`
Then commit: `fix(comvor): reflect stage edits in the flow editor before save`

---

### Task 2: Accurate dirty tracking (Discovery + Notifications)

**Problem:** `flowDirty` / `notificationsDirty` are one-way latches set `true` on any change and only cleared on save/reload. Reverting an edit by hand leaves "unsaved changes" showing (and would fire a no-op PUT).

**Fix:** capture a canonical **baseline snapshot** on load and after each successful save; make dirty a computed comparison `serialize(current) !== baselineSnapshot`. Compare a normalized/savable projection (not raw objects) so masked-token / shape noise never produces a false positive.

**Files:**
- Modify: `discovery/DiscoveryFlowTab.vue`
- Modify: `notifications/NotificationsTab.vue`
- Test: `discovery/specs/DiscoveryFlowTab.spec.js`, `notifications/specs/NotificationsTab.spec.js`

**Interfaces:**
- Consumes: Task 1's optimistic-apply (so `flowConfig.value` holds live edits to diff against baseline).
- Produces: `hasUnsavedChanges` / `notificationsDirty` become computed; revert-to-saved clears them.

- [ ] **Step 1: Write the failing tests**

`DiscoveryFlowTab.spec.js`: after load, assert `wrapper.vm.hasUnsavedChanges === false`; call `onStageUpdate({flow_key:'sales',stage_key:'discovery',on_complete:'handoff'})` → assert `true`; call `onStageUpdate({flow_key:'sales',stage_key:'discovery',on_complete:'continue'})` (revert to loaded value) → assert `hasUnsavedChanges === false`.

`NotificationsTab.spec.js`: load with one channel; toggle a field via the exposed `onNotificationsUpdate` to a new value → `notificationsDirty === true`; set it back to the loaded value → `notificationsDirty === false`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/DiscoveryFlowTab.spec.js notifications/specs/NotificationsTab.spec.js`
Expected: FAIL — dirty stays `true` after revert.

- [ ] **Step 3: Implement — DiscoveryFlowTab**

Add a `serializeFlows()` that projects only the editable per-stage fields, and a baseline ref:

```js
import isEqual from 'lodash/isEqual';

const flowBaseline = ref('');
function serializeFlows() {
  return JSON.stringify(
    (flowConfig.value?.flows || []).map(f => ({
      flow_key: f.flow_key,
      stages: (f.stages || []).map(s => ({
        stage_key: s.stage_key,
        on_complete: s.on_complete,
        action_mode: s.action_mode,
        guidance: s.guidance,
        skipped: s.skipped,
        notify_enabled: s.notify_enabled,
        notify_guidance: s.notify_guidance,
        enabled_reads: s.enabled_reads,
      })),
    }))
  );
}
```

In `applyFlowConfig`, after setting `flowConfig`/`versionId`, set `flowBaseline.value = serializeFlows()` and `draftStages.value = {}`. Replace the `flowDirty` ref + `hasUnsavedChanges` with:

```js
const hasUnsavedChanges = computed(() => serializeFlows() !== flowBaseline.value);
```

Remove standalone `flowDirty.value = ...` assignments in `onStageUpdate`/`saveDraft`; anywhere code reads `flowDirty.value` (e.g. publish gating, `openPublishModal`, publish button `:disabled`), replace with `hasUnsavedChanges.value`. Keep `draftStages` for the PUT payload; clear it in `applyFlowConfig` and after successful save. Update `defineExpose` (`flowDirty` → drop; keep `hasUnsavedChanges`).

- [ ] **Step 4: Implement — NotificationsTab**

Add a `serializeNotifications()` producing the exact PUT projection and a baseline:

```js
import isEqual from 'lodash/isEqual';

const notificationsBaseline = ref('');
function serializeNotifications() {
  const n = notifications.value || {};
  return JSON.stringify({
    channels: n.channels || [],
    subscriptions: n.subscriptions || [],
    muted_events: n.muted_events || [],
  });
}
```

Set `notificationsBaseline.value = serializeNotifications()` at the end of `loadNotifications` (after `notifications.value` is assigned). Replace the `notificationsDirty` ref with:

```js
const notificationsDirty = computed(
  () => serializeNotifications() !== notificationsBaseline.value
);
```

Remove the `notificationsDirty.value = true/false` assignments. Keep the computed in `defineExpose`.

> Note: `isEqual` import is optional if you compare serialized strings; keep whichever the implementer uses consistently. Prefer the string compare (stable + cheap).

- [ ] **Step 5: Run tests to verify they pass**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/DiscoveryFlowTab.spec.js notifications/specs/NotificationsTab.spec.js`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

Lint both files; commit: `fix(comvor): clear unsaved-changes flag when edits are reverted`

---

### Task 3: Single-marker journey strip

**Problem:** the strip reads as a passive breadcrumb; nothing signals it's interactive, and it has no explicit handoff boundary.

**Design:** the strip is a single **movable boundary**. Bot-zone pills are accent-tinted; a single **"Your team takes over"** marker sits immediately after the cutoff pill; post-cutoff pills stay muted. Remove the separate "Your team" terminus (redundant second team label). Add a one-line caption above the strip and pointer/hover affordance on every pill. A caption line beneath states the current split in plain language.

**Files:**
- Modify: `discovery/JourneyStrip.vue`
- Modify: `discovery/SalesFlowEditor.vue` (add caption above `<JourneyStrip>`; keep the existing post-cutoff `teamStages` rows and their `moveCutoffTo` click)
- i18n: add keys under `COMVOR_SETTINGS.DISCOVERY.JOURNEY`
- Test: `discovery/specs/JourneyStrip.spec.js`

**Interfaces:**
- Consumes: `stages` (array), `cutoffKey` (string) props; emits `selectCutoff(stageKey)` — unchanged from today.
- Produces: same events; only markup/affordance changes.

- [ ] **Step 1: Add i18n keys**

In `en.json` under `COMVOR_SETTINGS.DISCOVERY.JOURNEY` add:
- `CAPTION`: "Your bot handles the blue steps. Tap a step to choose where your team takes over."
- `TEAM_TAKES_OVER`: "Your team takes over"
- Keep existing `ARROW`, `YOUR_TEAM` (may drop `YOUR_TEAM` usage; leave the key).

In `SalesFlowEditor` i18n namespace add `COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.HANDOFF_SUMMARY_THROUGH` = "Your bot runs through “{stage}”, then your team takes over." and `HANDOFF_SUMMARY_ALL` = "Your bot runs the whole flow, then your team takes over."

- [ ] **Step 2: Write the failing test**

`JourneyStrip.spec.js`: mount with stages `[{stage_key:'a',display_name:'A'},{stage_key:'b',display_name:'B'},{stage_key:'c',display_name:'C'}]`, `cutoffKey:'b'`. Assert:
- there is exactly one element with `data-testid="handoff-marker"`, and it renders after the pill for `b` and before the pill for `c` (assert DOM order);
- there is **no** `data-testid="journey-terminus"`;
- clicking the pill `data-stage-key="c"` emits `selectCutoff` with `'c'`.

- [ ] **Step 3: Run test to verify it fails**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/JourneyStrip.spec.js`
Expected: FAIL (terminus still present, no marker).

- [ ] **Step 4: Implement JourneyStrip.vue**

Replace the template: render pills with `cursor-pointer` + hover ring (`hover:ring-2 hover:ring-n-brand/40 transition`), keep `data-testid="journey-step"` / `:data-stage-key` / `:data-zone`. After the pill whose index === `cutoffIndex`, render:

```html
<span
  v-if="index === cutoffIndex"
  data-testid="handoff-marker"
  class="shrink-0 inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-medium bg-n-brand/10 text-n-brand border border-dashed border-n-brand/40"
>
  {{ t('COMVOR_SETTINGS.DISCOVERY.JOURNEY.TEAM_TAKES_OVER') }}
</span>
```

Delete the terminus `<button data-testid="journey-terminus">` and the `lastStageKey()` helper (and the trailing arrow before it). Keep arrows *between* pills only. Keep `zoneFor`, `selectCutoff`.

- [ ] **Step 5: Implement SalesFlowEditor.vue caption**

Above `<JourneyStrip>` add a caption paragraph using `COMVOR_SETTINGS.DISCOVERY.JOURNEY.CAPTION`. Below the strip add a plain-language summary line: if `cutoffIndex` is the last stage, use `HANDOFF_SUMMARY_ALL`; else `HANDOFF_SUMMARY_THROUGH` with `{stage}` = the cutoff stage's `display_name`. (Compute from existing `cutoffKey`/`botStages`.)

- [ ] **Step 6: Run test + full discovery specs**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/`
Expected: PASS (update any existing JourneyStrip terminus assertions).

- [ ] **Step 7: Lint + commit**

Commit: `feat(comvor): make the journey strip a clear movable handoff control`

---

### Task 4: `?` help hint — real clickable affordance

**Problem:** each `?` is a `<span :title>` inside a control's `<label>`, so clicking it toggles/focuses the underlying control instead of showing help; hover-only help is invisible on touch and undiscoverable.

**Fix:** a shared `InfoHint.vue` — a `?` `<button type="button">` that on click (with `@click.stop.prevent`) toggles an inline help popover; keeps the `title` for hover. Replace every `?` span in the sales/notifications editors with it.

**Files:**
- Create: `discovery/InfoHint.vue`
- Modify: `discovery/SalesFlowEditor.vue` (3 `?` sites: who-completes, finish, notify — the notify one is removed in Task 5, so only who-completes + finish here), `discovery/NotificationsEditor.vue` (default, template `?` sites)
- Test: `discovery/specs/InfoHint.spec.js`

**Interfaces:**
- Produces: `<InfoHint :text="t('...')" />` — self-contained; no events needed.

- [ ] **Step 1: Write the failing test**

`InfoHint.spec.js`: mount `InfoHint` with `text:'Explains the thing'` wrapped inside a `<label><input type="checkbox"></label>` harness. Assert: help text is not visible initially; clicking the `?` button does NOT toggle the sibling checkbox (`checkbox.element.checked` unchanged) and DOES reveal an element containing `'Explains the thing'`; clicking again hides it.

- [ ] **Step 2: Run test to verify it fails**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/InfoHint.spec.js`
Expected: FAIL — component doesn't exist.

- [ ] **Step 3: Implement InfoHint.vue**

```html
<script setup>
import { ref } from 'vue';
defineProps({ text: { type: String, required: true } });
const open = ref(false);
</script>

<template>
  <span class="relative inline-block">
    <button
      type="button"
      data-testid="info-hint-toggle"
      :title="text"
      :aria-label="text"
      :aria-expanded="open"
      class="text-n-slate-9 cursor-help align-middle"
      @click.stop.prevent="open = !open"
    >
      ?
    </button>
    <span
      v-if="open"
      data-testid="info-hint-text"
      class="absolute left-0 top-5 z-10 w-56 rounded-md border border-n-weak bg-n-surface-1 p-2 text-xs font-normal text-n-slate-11 shadow"
    >
      {{ text }}
    </span>
  </span>
</template>
```

- [ ] **Step 4: Replace `?` spans**

In `SalesFlowEditor.vue`, replace the who-completes `?` span and the finish `?` span with `<InfoHint :text="t('...WHO_COMPLETES_TOOLTIP')" />` and `<InfoHint :text="t('...FINISH_TOOLTIP')" />`. Import `InfoHint`. (The notify `?` is removed with the whole notify block in Task 5.)

In `NotificationsEditor.vue`, replace the "Default" `?` span and the "Template" `?` span with `<InfoHint>` using the existing `DEFAULT_TOOLTIP` / `TEMPLATE_TOOLTIP` keys. Import `InfoHint`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/`
Expected: PASS.

- [ ] **Step 6: Lint + commit**

Commit: `fix(comvor): make ? help markers show help instead of toggling the control`

---

### Task 5: Unified notifications routing + retire the per-stage notify checkbox

**Problem:** "off" for a stage alert lives in two places — the flow-editor "Notify your team" checkbox (`notify_enabled`) AND the routing table's "Muted" option — and the routing rows are visually bloated.

**Design (agreed):** one control per event in the routing table: `Off · Default (starred channel) · <channel>…`. That single choice IS the enable. Remove the flow-editor notify checkbox + notify_guidance field; move the guidance into the routing row (shown when a specific channel is chosen). Defaults: `handoff`/`resolved` → **Default**; stage events → **Off**. Compact, dense rows grouped into "Conversation events" and "When a stage completes". Rows link `Off` to `notify_enabled=false` for stage events and to `muted_events` for fixed events; behind the scenes the Notifications tab writes stage `notify_enabled`/`notify_guidance` back through `PUT /flow-config` in addition to `PUT /notifications`.

**Files:**
- Modify: `discovery/NotificationsEditor.vue` (routing table — single control, dense layout, guidance-in-row, `Off` option; expose per-stage `notify_enabled`/`notify_guidance` changes upward)
- Modify: `notifications/NotificationsTab.vue` (on save, also PUT changed stage `notify_enabled`/`notify_guidance` to `/flow-config` with `expected_version_id`)
- Modify: `discovery/SalesFlowEditor.vue` (delete the `notifiable`/notify block; add a one-line "Team alerts for this stage are set in Notifications →" pointer for notifiable stages)
- i18n: add `ROUTE_OFF_OPTION` ("Off — don't notify"), group headers, guidance label, flow-editor pointer text
- Test: `discovery/specs/NotificationsEditor.spec.js`, `notifications/specs/NotificationsTab.spec.js`, `discovery/specs/SalesFlowEditor.spec.js`

**Interfaces:**
- `NotificationsEditor` emits, in addition to `update:notifications` (channels/subscriptions/muted_events), a new `update:stageNotify` payload: `{ stage_key, notify_enabled, notify_guidance }` whenever a stage-event row's route or guidance changes. `NotificationsTab` accumulates these and PUTs them to `/flow-config`.
- Each routing row's `route` select maps: `Off` → for a **stage** event, `notify_enabled=false` (no subscription, not muted); for a **fixed** event, add to `muted_events`. `Default` → `notify_enabled=true` (stage) / not muted (fixed), no subscription. A channel index → subscription row (+ `notify_enabled=true` for stage). The editor must know which events are stage events (prefix `stage:`) vs fixed.

- [ ] **Step 1: Write failing tests**

`NotificationsEditor.spec.js`:
- With no channels and default data, a stage-event row (`stage:order_drafting`) renders route select whose value is `Off` (top option), and the two fixed events (`handoff`/`resolved`) render value `Default`.
- Selecting `Off` on a stage row emits `update:stageNotify` with `{stage_key:'order_drafting', notify_enabled:false}`.
- Selecting `Default` on a stage row emits `update:stageNotify` with `notify_enabled:true` and emits `update:notifications` with no subscription/mute for that event.
- Selecting `Off` on a fixed row (`handoff`) emits `update:notifications` with `handoff` in `muted_events`.
- The routing rows render single-line (assert no per-row "Channel" label element; assert one group header "When a stage completes" and one "Conversation events").
- The template/guidance input only renders when a row is routed to a numeric channel.

`NotificationsTab.spec.js`: when a `update:stageNotify` has fired and `saveNotifications` runs, assert a `PUT` to `/flow-config` is issued with a `stages` array containing `{flow_key, stage_key, notify_enabled, ...}` and `expected_version_id`, in addition to the `PUT /notifications`.

`SalesFlowEditor.spec.js`: a notifiable stage renders the "set in Notifications" pointer and does NOT render `data-testid="notify-toggle"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/NotificationsEditor.spec.js notifications/specs/NotificationsTab.spec.js discovery/specs/SalesFlowEditor.spec.js`
Expected: FAIL.

- [ ] **Step 3: Implement NotificationsEditor routing rework**

- Distinguish stage events: `isStageEvent = row.event.startsWith('stage:')`; map `stage:<key>` → `stage_key`.
- Seed each row's `route`: for stage events, `notify_enabled===false` → `Off`, else subscription→channel index, else `Default`. For fixed events, muted→`Off`(represented internally still as muted), subscription→channel, else `Default`. Collapse the old `ROUTE_MUTED` into the single top `Off` option.
- Route select options: `Off` (value `off`), then `Default`, then channels. Remove the separate "Muted" option.
- `onRouteChange`: compute the new route; for stage events emit `update:stageNotify {stage_key, notify_enabled: route!=='off', notify_guidance}`; for fixed events, `off` → ensure event in `muted_events`, else remove from `muted_events`. In all cases rebuild `subscriptions` from numeric routes. Call `emitUpdate()` (channels/subscriptions/muted_events) as today.
- Move the per-row guidance/template: when route is a numeric channel, show the template input (as today). Additionally, for **stage** events show a `notify_guidance` text input (single line) whenever route !== `off`; changing it emits `update:stageNotify` with the new guidance. (Keep `template` and `notify_guidance` as separate inputs for now; a later pass may merge them.)
- Rebuild the rows markup as dense single-line rows inside one card, with two group subheaders. Follow the compact layout: `flex items-center justify-between gap-3 px-3 py-2.5 border-b`. Remove the per-row "Channel" `<span>` label; add one column header row.

- [ ] **Step 4: Implement NotificationsTab dual-save**

- Track stage-notify edits: add `stageNotifyDraft` (`ref({})` keyed by `stage_key`) and an `onStageNotify(update)` handler merging partial fields. Bind `@update:stageNotify="onStageNotify"` on `<NotificationsEditor>`.
- Capture flow-config `version_id` in `loadNotifiableStages` (it already fetches `/flow-config`); store in `flowVersionId`.
- In `saveNotifications`: first `PUT /notifications` (as today). If `stageNotifyDraft` non-empty, also `PUT /flow-config` with body `{ stages: Object.values(stageNotifyDraft).map(s => ({ flow_key:'sales', stage_key:s.stage_key, notify_enabled:s.notify_enabled, notify_guidance:s.notify_guidance })), expected_version_id: flowVersionId.value }`. On 409, alert + reload (mirror DiscoveryFlowTab's conflict handling). Clear `stageNotifyDraft` and reload on success.
- Fold `stageNotifyDraft` non-empty into the dirty computation from Task 2.

> Confirm the `flow_key` for the ordered flow is `sales` by inspecting the loaded `/flow-config` (`flows[].flow_key` where `mode==='ordered'`) rather than hard-coding — derive it from `notifiableStages` load. Store `flow_key` per notifiable stage in `extractNotifiableStages`.

- [ ] **Step 5: Implement SalesFlowEditor notify removal**

Delete the entire `v-if="stage.notifiable"` notify block (checkbox + guidance). For notifiable stages, render instead a muted one-line pointer: `{{ t('COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_MOVED_POINTER') }}` (= "Team alerts for this step are set in the Notifications tab."). Remove now-unused `setNotifyEnabled`/`setNotifyGuidance` if not referenced elsewhere.

- [ ] **Step 6: Run tests to verify they pass**

Run: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- discovery/specs/ notifications/specs/`
Expected: PASS. Update any stale existing assertions (old muted option, old notify toggle).

- [ ] **Step 7: Lint + commit**

Commit: `feat(comvor): unify stage-alert enabling into the notifications routing table`

---

### Task 6: Slice verification

- [ ] **Step 1:** Run the full comvor UI suite: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm test -- app/javascript/dashboard/routes/dashboard/settings/comvor/`
- [ ] **Step 2:** Lint all touched files: `PATH=~/.nvm/versions/node/v22.21.0/bin:$PATH pnpm exec eslint app/javascript/dashboard/routes/dashboard/settings/comvor/`
- [ ] **Step 3:** Confirm `en.json` has every new key referenced; no `[MISSING]` at runtime.
- [ ] **Step 4:** Commit any lint fixes: `chore(comvor): slice A verification`
