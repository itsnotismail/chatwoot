import { shallowMount, flushPromises } from '@vue/test-utils';
import WhatsappEmbeddedSignup from '../WhatsappEmbeddedSignup.vue';
import NextButton from 'next/button/Button.vue';
import { initWhatsAppEmbeddedSignup } from '../whatsapp/utils';
import { useAlert } from 'dashboard/composables';

const dispatch = vi.fn();
const replace = vi.fn();

vi.mock('vuex', () => ({ useStore: () => ({ dispatch }) }));
vi.mock('vue-router', () => ({ useRouter: () => ({ replace }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key }),
  I18nT: { template: '<span />' },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('../whatsapp/utils', async importOriginal => ({
  ...(await importOriginal()),
  setupFacebookSdk: vi.fn().mockResolvedValue(),
  initWhatsAppEmbeddedSignup: vi.fn(),
}));

// Meta posts the session info from the popup; only *.facebook.com origins are read.
const postSignupEvent = (event, data) =>
  window.dispatchEvent(
    new MessageEvent('message', {
      origin: 'https://www.facebook.com',
      data: JSON.stringify({ type: 'WA_EMBEDDED_SIGNUP', event, data }),
    })
  );

const mountSignup = () =>
  shallowMount(WhatsappEmbeddedSignup, {
    global: { mocks: { $t: key => key } },
  });

const launch = async wrapper => {
  wrapper.findComponent(NextButton).vm.$emit('click');
  await flushPromises();
};

describe('WhatsappEmbeddedSignup', () => {
  let wrapper;

  beforeEach(() => {
    vi.clearAllMocks();
    initWhatsAppEmbeddedSignup.mockResolvedValue('auth-code');
    dispatch.mockResolvedValue({ id: 7 });
    wrapper = mountSignup();
  });

  afterEach(() => wrapper.unmount());

  it('connects a coexistence number from a waba_id-only completion', async () => {
    await launch(wrapper);
    postSignupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
      waba_id: 'waba-1',
    });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createWhatsAppEmbeddedSignup',
      expect.objectContaining({
        code: 'auth-code',
        waba_id: 'waba-1',
        phone_number_id: '',
        is_coexistence: true,
      })
    );
    expect(replace).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'settings_inboxes_add_agents' })
    );
  });

  it('marks a new-number FINISH as not coexistence, even when it beats the auth code', async () => {
    initWhatsAppEmbeddedSignup.mockImplementation(async () => {
      postSignupEvent('FINISH', {
        waba_id: 'waba-1',
        business_id: 'biz-1',
        phone_number_id: 'phone-1',
      });
      return 'auth-code';
    });
    await launch(wrapper);

    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createWhatsAppEmbeddedSignup',
      expect.objectContaining({
        business_id: 'biz-1',
        phone_number_id: 'phone-1',
        is_coexistence: false,
      })
    );
  });

  it('posts once, as coexistence, when a normal FINISH follows the coexistence one', async () => {
    initWhatsAppEmbeddedSignup.mockImplementation(async () => {
      postSignupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
        waba_id: 'waba-1',
      });
      postSignupEvent('FINISH', { waba_id: 'waba-1', phone_number_id: 'p-1' });
      return 'auth-code';
    });
    await launch(wrapper);
    postSignupEvent('FINISH', { waba_id: 'waba-1', phone_number_id: 'p-1' });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createWhatsAppEmbeddedSignup',
      expect.objectContaining({ is_coexistence: true })
    );
  });

  it('forgets a previous attempt when the merchant launches again', async () => {
    initWhatsAppEmbeddedSignup.mockImplementationOnce(async () => {
      postSignupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
        waba_id: 'old-waba',
      });
      throw new Error('Login cancelled');
    });
    await launch(wrapper);
    expect(dispatch).not.toHaveBeenCalled();

    await launch(wrapper);
    postSignupEvent('FINISH', { waba_id: 'new-waba', phone_number_id: 'p-2' });
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith(
      'inboxes/createWhatsAppEmbeddedSignup',
      expect.objectContaining({ waba_id: 'new-waba', is_coexistence: false })
    );
  });

  it('shows the v4 ERROR message and creates nothing', async () => {
    await launch(wrapper);
    postSignupEvent('ERROR', { error_message: 'Number is not eligible' });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith('Number is not eligible');
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('explains a completion that shared no phone number', async () => {
    await launch(wrapper);
    postSignupEvent('FINISH_ONLY_WABA', { waba_id: 'waba-1' });
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.UNSUPPORTED_COMPLETION'
    );
    expect(dispatch).not.toHaveBeenCalled();
  });
});
