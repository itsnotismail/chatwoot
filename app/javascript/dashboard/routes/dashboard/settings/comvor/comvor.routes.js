import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/comvor'),
      meta: { permissions: ['administrator'] },
      component: SettingsWrapper,
      props: {
        headerTitle: 'COMVOR_SETTINGS.TITLE',
        icon: 'i-lucide-bot-message-square',
        showNewButton: false,
      },
      children: [
        {
          path: '',
          name: 'comvor_settings_index',
          component: Index,
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
