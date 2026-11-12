import { shallowMount, flushPromises } from '@vue/test-utils';
import Reauthorize from '../Reauthorize.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import { initWhatsAppEmbeddedSignup } from '../utils';

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/channel/whatsappChannel', () => ({
  default: { reauthorizeWhatsApp: vi.fn() },
}));
vi.mock('../utils', async importOriginal => ({
  ...(await importOriginal()),
  setupFacebookSdk: vi.fn().mockResolvedValue(),
  initWhatsAppEmbeddedSignup: vi.fn(),
}));

const postSignupEvent = (event, data) =>
  window.dispatchEvent(
    new MessageEvent('message', {
      origin: 'https://www.facebook.com',
      data: JSON.stringify({ type: 'WA_EMBEDDED_SIGNUP', event, data }),
    })
  );

const mountReauthorize = providerConfig =>
  shallowMount(Reauthorize, {
    props: { inbox: { id: 9, provider_config: providerConfig } },
  });

describe('Reauthorize (WhatsApp)', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    window.chatwootConfig = {
      whatsappAppId: 'app',
      whatsappConfigurationId: 'config',
    };
    whatsappChannel.reauthorizeWhatsApp.mockResolvedValue({
      data: { success: true },
    });
  });

  // Meta usually posts FINISH before FB.login's callback fires.
  it('reauthorizes a coexistence number whose FINISH beat the auth code', async () => {
    initWhatsAppEmbeddedSignup.mockImplementation(async () => {
      postSignupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
        waba_id: 'waba-1',
      });
      return 'auth-code';
    });
    const wrapper = mountReauthorize({});
    await flushPromises();

    await wrapper.vm.requestAuthorization();
    await flushPromises();

    expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledTimes(1);
    expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith(
      expect.objectContaining({
        inboxId: 9,
        code: 'auth-code',
        waba_id: 'waba-1',
        phone_number_id: '',
        is_coexistence: true,
      })
    );
  });

  it('passes the coexistence signal on the stored-config shortcut too', async () => {
    initWhatsAppEmbeddedSignup.mockImplementation(async () => {
      postSignupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
        waba_id: 'waba-1',
      });
      return 'auth-code';
    });
    const wrapper = mountReauthorize({
      business_account_id: 'waba-1',
      phone_number_id: 'phone-1',
    });
    await flushPromises();

    await wrapper.vm.requestAuthorization();
    await flushPromises();

    expect(whatsappChannel.reauthorizeWhatsApp).toHaveBeenCalledWith(
      expect.objectContaining({
        waba_id: 'waba-1',
        phone_number_id: 'phone-1',
        is_coexistence: true,
      })
    );
  });
});
