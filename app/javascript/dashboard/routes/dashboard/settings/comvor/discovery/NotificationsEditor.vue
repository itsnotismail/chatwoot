<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InfoHint from './InfoHint.vue';

const props = defineProps({
  notifications: { type: Object, required: true },
  notifiableStages: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:notifications', 'update:stageNotify']);

const { t } = useI18n();

// Telegram bot tokens are write-only: the backend masks a saved token as
// this sentinel in GET responses, and accepts it back in PUT bodies to mean
// "keep the stored token unchanged".
const TOKEN_MASK = '********';

// Sentinel channel-select value meaning "no explicit subscription — falls to
// the starred default channel". Distinct from any real channel index and
// from the "off" sentinel below.
const ROUTE_DEFAULT = 'default';
const ROUTE_OFF = 'off';
const TEMPLATE_MAX = 1000;
const NOTIFY_GUIDANCE_MAX = 500;

const isGuideOpen = ref(false);

// Local channels are {id, bot_token, chat_id, enabled, isDefault, tokenTyped}
// rows. `id` is 0/undefined for a channel not yet persisted. `bot_token` is
// never seeded with the mask — for an existing channel whose fetched token
// is masked, the input starts empty (with a placeholder) and `tokenTyped`
// tracks whether the user has entered a replacement.
const channels = reactive([]);

// One row per routable event: the two fixed events plus one per notifiable
// stage. `route` is either ROUTE_DEFAULT, ROUTE_OFF, or a channel index
// (number). `template` is only meaningful when `route` is a channel index.
// Stage rows additionally carry `isStage`, `flowKey`, and `guidance`.
const routes = reactive([]);

function fixedEventRows() {
  return [
    {
      event: 'handoff',
      labelKey: 'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_HANDOFF',
      isStage: false,
    },
    {
      event: 'resolved',
      labelKey: 'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_RESOLVED',
      isStage: false,
    },
  ];
}

function stageEventRows() {
  return props.notifiableStages.map(s => ({
    event: `stage:${s.stage_key}`,
    label: t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_STAGE_COMPLETED', {
      stage: s.display_name || s.stage_key,
    }),
    isStage: true,
    stageKey: s.stage_key,
    flowKey: s.flow_key,
  }));
}

function seedChannels(list) {
  channels.splice(
    0,
    channels.length,
    ...(list || []).map(c => {
      const fetchedToken = c.config?.bot_token || '';
      const isMasked = fetchedToken === TOKEN_MASK;
      return {
        id: c.id || 0,
        bot_token: isMasked ? '' : fetchedToken,
        chat_id: c.config?.chat_id || '',
        enabled: !!c.enabled,
        isDefault: !!c.is_default,
        tokenTyped: false,
      };
    })
  );
}

function seedRoutes(notifications, channelList) {
  const idToIndex = new Map(
    (channelList || []).map((c, index) => [c.id, index])
  );
  const subsByEvent = new Map(
    (notifications.subscriptions || [])
      .filter(s => idToIndex.has(s.channel_id))
      .map(s => [s.event, s])
  );
  const mutedEvents = new Set(notifications.muted_events || []);

  const eventRows = [...fixedEventRows(), ...stageEventRows()];
  const stagesByKey = new Map(
    props.notifiableStages.map(s => [s.stage_key, s])
  );

  routes.splice(
    0,
    routes.length,
    ...eventRows.map(row => {
      const sub = subsByEvent.get(row.event);
      const base = {
        event: row.event,
        isStage: row.isStage,
        stageKey: row.stageKey,
        flowKey: row.flowKey,
        guidance: row.isStage
          ? stagesByKey.get(row.stageKey)?.notify_guidance || ''
          : '',
      };

      if (row.isStage) {
        const stage = stagesByKey.get(row.stageKey);
        if (stage?.notify_enabled === false) {
          return { ...base, route: ROUTE_OFF, template: '' };
        }
        if (sub) {
          return {
            ...base,
            route: idToIndex.get(sub.channel_id),
            template: sub.template || '',
          };
        }
        return { ...base, route: ROUTE_DEFAULT, template: '' };
      }

      if (sub) {
        return {
          ...base,
          route: idToIndex.get(sub.channel_id),
          template: sub.template || '',
        };
      }
      if (mutedEvents.has(row.event)) {
        return { ...base, route: ROUTE_OFF, template: '' };
      }
      return { ...base, route: ROUTE_DEFAULT, template: '' };
    })
  );
}

watch(
  () => [props.notifications, props.notifiableStages],
  ([notifications]) => {
    seedChannels(notifications.channels);
    seedRoutes(notifications, notifications.channels);
  },
  { immediate: true, deep: true }
);

const hasDefaultChannel = computed(() => channels.some(c => c.isDefault));

function emitUpdate() {
  emit('update:notifications', {
    channels: channels.map(c => ({
      id: c.id,
      kind: 'telegram',
      config: {
        // Existing channel, untouched token → send the sentinel so the
        // backend keeps the stored token. Otherwise send whatever the user
        // typed (empty for an untouched new channel, which the Save button
        // gates on).
        bot_token: !c.tokenTyped && c.id ? TOKEN_MASK : c.bot_token,
        chat_id: c.chat_id,
      },
      enabled: c.enabled,
      is_default: c.isDefault,
    })),
    // "Default" (no explicit subscription, not muted/disabled) → no entry in
    // either list. A specific channel → a subscription row. "Off" on a fixed
    // event → a muted_events entry (stage events never appear in
    // muted_events; their "off" is notify_enabled=false on the stage
    // instead). Guard against a route referencing a channel index that no
    // longer exists (e.g. all channels were removed).
    subscriptions: routes
      .filter(
        r =>
          typeof r.route === 'number' &&
          r.route >= 0 &&
          r.route < channels.length
      )
      .map(r => ({
        event: r.event,
        channel_index: r.route,
        template: r.template,
      })),
    muted_events: routes
      .filter(r => !r.isStage && r.route === ROUTE_OFF)
      .map(r => r.event),
  });
}

function emitStageNotify(route, fields) {
  emit('update:stageNotify', {
    flow_key: route.flowKey,
    stage_key: route.stageKey,
    ...fields,
  });
}

function onChannelField(index, field, value) {
  channels[index][field] = value;
  if (field === 'bot_token') {
    channels[index].tokenTyped = true;
  }
  emitUpdate();
}

function setDefaultChannel(index) {
  channels.forEach((c, i) => {
    c.isDefault = i === index;
  });
  emitUpdate();
}

function addChannel() {
  channels.push({
    id: 0,
    bot_token: '',
    chat_id: '',
    enabled: true,
    isDefault: channels.length === 0,
    tokenTyped: false,
  });
  emitUpdate();
}

function removeChannel(index) {
  const wasDefault = channels[index].isDefault;
  channels.splice(index, 1);
  if (wasDefault && channels.length) {
    channels[0].isDefault = true;
  }
  // Routes pointing at the removed channel fall back to Default; shift the
  // rest down.
  routes.forEach(r => {
    if (r.route === index) {
      r.route = ROUTE_DEFAULT;
      r.template = '';
    } else if (typeof r.route === 'number' && r.route > index) {
      r.route -= 1;
    }
  });
  emitUpdate();
}

function onRouteChange(index, value) {
  const route =
    value === ROUTE_DEFAULT || value === ROUTE_OFF ? value : Number(value);
  const row = routes[index];
  row.route = route;
  // Template overrides only apply when routed to a specific channel.
  if (typeof route !== 'number') {
    row.template = '';
  }

  if (row.isStage) {
    // Stage event: the route choice IS the enable/disable — Off means the
    // stage event never fires, Default/channel both mean it fires (with or
    // without an explicit subscription).
    emitStageNotify(row, { notify_enabled: route !== ROUTE_OFF });
    // Subscriptions/muted_events still need to reflect the channel choice
    // (or its absence) for this stage event.
    emitUpdate();
  } else {
    emitUpdate();
  }
}

function onRouteTemplate(index, value) {
  routes[index].template = value;
  emitUpdate();
}

function onRouteGuidance(index, value) {
  const row = routes[index];
  row.guidance = value;
  emitStageNotify(row, { notify_guidance: value });
}

function channelLabel(channel, index) {
  return channel.chat_id
    ? t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNEL_OPTION_WITH_CHAT_ID', {
        index: index + 1,
        chatId: channel.chat_id,
      })
    : t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNEL_OPTION', {
        index: index + 1,
      });
}

function routeLabel(row) {
  return row.label || t(row.labelKey);
}

const allRows = computed(() => {
  const eventRows = [...fixedEventRows(), ...stageEventRows()];
  return routes.map((r, i) => ({
    ...r,
    label: routeLabel(eventRows.find(e => e.event === r.event) || {}),
    index: i,
  }));
});

const conversationRows = computed(() => allRows.value.filter(r => !r.isStage));
const stageRows = computed(() => allRows.value.filter(r => r.isStage));
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-3">
      <h5 class="font-medium text-sm text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNELS_TITLE') }}
      </h5>

      <div
        v-if="!channels.length"
        data-testid="botfather-empty-state"
        class="border rounded-md p-3 flex flex-col gap-2"
      >
        <button
          type="button"
          data-testid="botfather-guide-toggle"
          class="flex items-center justify-between gap-2 text-left text-sm font-medium text-n-slate-12"
          @click="isGuideOpen = !isGuideOpen"
        >
          <span>{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOTFATHER_GUIDE_TITLE')
          }}</span>
          <span class="text-xs text-n-slate-9" aria-hidden="true">{{
            isGuideOpen
              ? t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.COLLAPSE_LABEL')
              : t('COMVOR_SETTINGS.DISCOVERY.SUPPORT_EDITOR.EXPAND_LABEL')
          }}</span>
        </button>
        <ol
          v-if="isGuideOpen"
          data-testid="botfather-guide-steps"
          class="list-decimal list-inside text-xs text-n-slate-11 flex flex-col gap-1"
        >
          <li>
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOTFATHER_STEP_1') }}
          </li>
          <li>
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOTFATHER_STEP_2') }}
          </li>
          <li>
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOTFATHER_STEP_3') }}
          </li>
        </ol>
      </div>

      <div
        v-for="(channel, index) in channels"
        :key="index"
        class="flex flex-wrap items-end gap-2 border rounded-md p-3"
      >
        <label class="flex items-center gap-2">
          <input
            data-testid="channel-default-radio"
            type="radio"
            name="default-channel"
            :checked="channel.isDefault"
            class="w-4 h-4 accent-n-brand"
            @change="setDefaultChannel(index)"
          />
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.DEFAULT_LABEL') }}
            <InfoHint
              :text="
                t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.DEFAULT_TOOLTIP')
              "
            />
          </span>
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOT_TOKEN_LABEL')
          }}</span>
          <input
            data-testid="channel-bot-token-input"
            type="text"
            :value="channel.bot_token"
            :placeholder="
              channel.id && !channel.tokenTyped
                ? t(
                    'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOT_TOKEN_SAVED_PLACEHOLDER'
                  )
                : null
            "
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="onChannelField(index, 'bot_token', $event.target.value)"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHAT_ID_LABEL') }}
            <InfoHint
              :text="
                t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHAT_ID_TOOLTIP')
              "
            />
          </span>
          <input
            data-testid="channel-chat-id-input"
            type="text"
            :value="channel.chat_id"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="onChannelField(index, 'chat_id', $event.target.value)"
          />
        </label>

        <label class="flex items-center gap-2">
          <input
            data-testid="channel-enabled-checkbox"
            type="checkbox"
            :checked="channel.enabled"
            class="w-4 h-4 accent-n-brand"
            @change="onChannelField(index, 'enabled', $event.target.checked)"
          />
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ENABLED_LABEL')
          }}</span>
        </label>

        <button
          data-testid="remove-channel-button"
          type="button"
          class="text-xs text-red-600"
          @click="removeChannel(index)"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.REMOVE_CHANNEL') }}
        </button>
      </div>

      <button
        data-testid="add-channel-button"
        type="button"
        class="self-start text-xs text-n-brand"
        @click="addChannel"
      >
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ADD_CHANNEL') }}
      </button>

      <p
        v-if="channels.length && !hasDefaultChannel"
        data-testid="no-default-channel-hint"
        class="text-xs text-amber-600"
      >
        {{
          t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.NO_DEFAULT_CHANNEL_HINT')
        }}
      </p>
    </div>

    <div class="flex flex-col gap-1">
      <h5 class="font-medium text-sm text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ROUTING_TITLE') }}
      </h5>

      <div class="border rounded-md overflow-hidden">
        <template v-if="conversationRows.length">
          <div
            class="px-3 py-1.5 text-xs font-medium text-n-slate-10 bg-n-slate-2"
          >
            {{
              t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.GROUP_CONVERSATION')
            }}
          </div>
          <div
            v-for="row in conversationRows"
            :key="row.event"
            data-testid="routing-row"
            class="flex items-center justify-between gap-3 px-3 py-2.5 border-b last:border-b-0"
          >
            <span class="text-sm text-n-slate-12 flex-1 min-w-0">{{
              row.label
            }}</span>

            <select
              data-testid="route-channel-select"
              :value="row.route"
              :aria-label="
                t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SEND_TO_LABEL')
              "
              class="w-64 shrink-0 rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              @change="onRouteChange(row.index, $event.target.value)"
            >
              <option :value="ROUTE_OFF">
                {{
                  t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ROUTE_OFF_OPTION')
                }}
              </option>
              <option :value="ROUTE_DEFAULT">
                {{
                  t(
                    'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ROUTE_DEFAULT_OPTION'
                  )
                }}
              </option>
              <option
                v-for="(channel, channelIndex) in channels"
                :key="channelIndex"
                :value="channelIndex"
              >
                {{ channelLabel(channel, channelIndex) }}
              </option>
            </select>

            <label
              v-if="typeof row.route === 'number'"
              class="flex flex-col gap-1"
            >
              <input
                data-testid="route-template-input"
                type="text"
                :value="row.template"
                :maxlength="TEMPLATE_MAX"
                :placeholder="
                  t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TEMPLATE_LABEL')
                "
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                @change="onRouteTemplate(row.index, $event.target.value)"
              />
            </label>
          </div>
        </template>

        <template v-if="stageRows.length">
          <div
            class="px-3 py-1.5 text-xs font-medium text-n-slate-10 bg-n-slate-2"
          >
            {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.GROUP_STAGE') }}
          </div>
          <div
            v-for="row in stageRows"
            :key="row.event"
            data-testid="routing-row"
            class="flex items-center justify-between gap-3 px-3 py-2.5 border-b last:border-b-0"
          >
            <span class="text-sm text-n-slate-12 flex-1 min-w-0">{{
              row.label
            }}</span>

            <select
              data-testid="route-channel-select"
              :value="row.route"
              :aria-label="
                t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SEND_TO_LABEL')
              "
              class="w-64 shrink-0 rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
              @change="onRouteChange(row.index, $event.target.value)"
            >
              <option :value="ROUTE_OFF">
                {{
                  t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ROUTE_OFF_OPTION')
                }}
              </option>
              <option :value="ROUTE_DEFAULT">
                {{
                  t(
                    'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ROUTE_DEFAULT_OPTION'
                  )
                }}
              </option>
              <option
                v-for="(channel, channelIndex) in channels"
                :key="channelIndex"
                :value="channelIndex"
              >
                {{ channelLabel(channel, channelIndex) }}
              </option>
            </select>

            <label
              v-if="typeof row.route === 'number'"
              class="flex flex-col gap-1"
            >
              <input
                data-testid="route-template-input"
                type="text"
                :value="row.template"
                :maxlength="TEMPLATE_MAX"
                :placeholder="
                  t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TEMPLATE_LABEL')
                "
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                @change="onRouteTemplate(row.index, $event.target.value)"
              />
            </label>

            <label v-if="row.route !== ROUTE_OFF" class="flex flex-col gap-1">
              <input
                data-testid="route-guidance-input"
                type="text"
                :value="row.guidance"
                :maxlength="NOTIFY_GUIDANCE_MAX"
                :placeholder="
                  t(
                    'COMVOR_SETTINGS.DISCOVERY.SALES_EDITOR.NOTIFY_GUIDANCE_LABEL'
                  )
                "
                class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
                @change="onRouteGuidance(row.index, $event.target.value)"
              />
            </label>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>
