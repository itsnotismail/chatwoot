<script setup>
import { reactive, watch } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  notifications: { type: Object, required: true },
});

const emit = defineEmits(['update:notifications']);

const { t } = useI18n();

// Local channels are plain {bot_token, chat_id, enabled} rows (no id — the
// backend assigns ids on save). Local subscriptions track `channelIndex`
// (the 0-based position in `channels`) rather than the DB `channel_id`, so
// the channel <select> can bind directly to array position.
const channels = reactive([]);
const subscriptions = reactive([]);

function seedChannels(list) {
  channels.splice(
    0,
    channels.length,
    ...(list || []).map(c => ({
      bot_token: c.config?.bot_token || '',
      chat_id: c.config?.chat_id || '',
      enabled: !!c.enabled,
    }))
  );
}

function seedSubscriptions(list, channelList) {
  const idToIndex = new Map(
    (channelList || []).map((c, index) => [c.id, index])
  );
  subscriptions.splice(
    0,
    subscriptions.length,
    ...(list || [])
      .filter(s => idToIndex.has(s.channel_id))
      .map(s => ({
        event: s.event,
        channelIndex: idToIndex.get(s.channel_id),
        template: s.template || '',
      }))
  );
}

watch(
  () => props.notifications,
  notifications => {
    seedChannels(notifications.channels);
    seedSubscriptions(notifications.subscriptions, notifications.channels);
  },
  { immediate: true }
);

function emitUpdate() {
  emit('update:notifications', {
    channels: channels.map(c => ({
      kind: 'telegram',
      config: { bot_token: c.bot_token, chat_id: c.chat_id },
      enabled: c.enabled,
    })),
    // Guard against a subscription referencing a channel index that no
    // longer exists (e.g. all channels were removed) — never emit a bogus
    // channel_index.
    subscriptions: subscriptions
      .filter(s => s.channelIndex >= 0 && s.channelIndex < channels.length)
      .map(s => ({
        event: s.event,
        channel_index: s.channelIndex,
        template: s.template,
      })),
  });
}

function onChannelField(index, field, value) {
  channels[index][field] = value;
  emitUpdate();
}

function addChannel() {
  channels.push({ bot_token: '', chat_id: '', enabled: true });
  emitUpdate();
}

function removeChannel(index) {
  channels.splice(index, 1);
  // Drop subscriptions pointing at the removed channel; shift the rest down.
  for (let i = subscriptions.length - 1; i >= 0; i -= 1) {
    const sub = subscriptions[i];
    if (sub.channelIndex === index) {
      subscriptions.splice(i, 1);
    } else if (sub.channelIndex > index) {
      sub.channelIndex -= 1;
    }
  }
  emitUpdate();
}

function onSubscriptionField(index, field, value) {
  subscriptions[index][field] = value;
  emitUpdate();
}

function addSubscription() {
  subscriptions.push({ event: 'handoff', channelIndex: 0, template: '' });
  emitUpdate();
}

function removeSubscription(index) {
  subscriptions.splice(index, 1);
  emitUpdate();
}
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-col gap-3">
      <h5 class="font-medium text-sm text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNELS_TITLE') }}
      </h5>
      <div
        v-for="(channel, index) in channels"
        :key="index"
        class="flex flex-wrap items-end gap-2 border rounded-md p-3"
      >
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.BOT_TOKEN_LABEL')
          }}</span>
          <input
            data-testid="channel-bot-token-input"
            type="text"
            :value="channel.bot_token"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="onChannelField(index, 'bot_token', $event.target.value)"
          />
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHAT_ID_LABEL')
          }}</span>
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
    </div>

    <div class="flex flex-col gap-3">
      <h5 class="font-medium text-sm text-n-slate-12">
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.SUBSCRIPTIONS_TITLE') }}
      </h5>
      <div
        v-for="(subscription, index) in subscriptions"
        :key="index"
        class="flex flex-wrap items-end gap-2 border rounded-md p-3"
      >
        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_LABEL')
          }}</span>
          <select
            data-testid="subscription-event-select"
            :value="subscription.event"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="onSubscriptionField(index, 'event', $event.target.value)"
          >
            <option value="handoff">
              {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_HANDOFF') }}
            </option>
            <option value="resolved">
              {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.EVENT_RESOLVED') }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNEL_LABEL')
          }}</span>
          <select
            data-testid="subscription-channel-select"
            :value="subscription.channelIndex"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="
              onSubscriptionField(
                index,
                'channelIndex',
                Number($event.target.value)
              )
            "
          >
            <option
              v-for="(channel, channelIndex) in channels"
              :key="channelIndex"
              :value="channelIndex"
            >
              {{ channel.chat_id
              }}{{
                channel.chat_id
                  ? ''
                  : t(
                      'COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.CHANNEL_OPTION',
                      {
                        index: channelIndex,
                      }
                    )
              }}
            </option>
          </select>
        </label>

        <label class="flex flex-col gap-1 grow">
          <span class="text-xs font-medium text-n-slate-12">{{
            t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.TEMPLATE_LABEL')
          }}</span>
          <textarea
            data-testid="subscription-template-input"
            :value="subscription.template"
            rows="2"
            class="rounded-lg border border-n-weak bg-n-surface-1 px-3 py-2 text-sm text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
            @change="
              onSubscriptionField(index, 'template', $event.target.value)
            "
          />
        </label>

        <button
          data-testid="remove-subscription-button"
          type="button"
          class="text-xs text-red-600"
          @click="removeSubscription(index)"
        >
          {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.REMOVE_SUBSCRIPTION') }}
        </button>
      </div>

      <button
        data-testid="add-subscription-button"
        type="button"
        class="self-start text-xs text-n-brand"
        @click="addSubscription"
      >
        {{ t('COMVOR_SETTINGS.DISCOVERY.NOTIFICATIONS.ADD_SUBSCRIPTION') }}
      </button>
    </div>
  </div>
</template>
