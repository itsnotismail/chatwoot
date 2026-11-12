import {
  EMBEDDED_SIGNUP_EXTRAS,
  SIGNUP_RESULT,
  classifySignupEvent,
  initWhatsAppEmbeddedSignup,
  isValidBusinessData,
} from '../utils';

// Payload shapes from Meta's Embedded Signup v4 implementation and coexistence docs:
// https://developers.facebook.com/docs/whatsapp/embedded-signup/implementation
// https://developers.facebook.com/docs/whatsapp/embedded-signup/custom-flows/onboarding-business-app-users
const signupEvent = (event, data = {}) => ({
  type: 'WA_EMBEDDED_SIGNUP',
  event,
  data,
});

describe('initWhatsAppEmbeddedSignup', () => {
  afterEach(() => {
    delete window.FB;
  });

  it('launches Embedded Signup v4 explicitly, with coexistence offered', async () => {
    const login = vi.fn(callback =>
      callback({ authResponse: { code: 'the-code' } })
    );
    window.FB = { login };

    await expect(initWhatsAppEmbeddedSignup('config-123')).resolves.toBe(
      'the-code'
    );

    const options = login.mock.calls[0][1];
    expect(options).toMatchObject({
      config_id: 'config-123',
      response_type: 'code',
      override_default_response_type: true,
    });
    expect(options.extras).toEqual({
      setup: {},
      featureType: 'whatsapp_business_app_onboarding',
      version: 'v4',
    });
    // A v2-only input; v4 sends session info for every flow.
    expect(options.extras).not.toHaveProperty('sessionInfoVersion');
  });

  it('hands the SDK a copy, so the shared extras stay untouched', async () => {
    window.FB = {
      login: vi.fn((callback, options) => {
        options.extras.version = 'mutated';
        callback({ authResponse: { code: 'c' } });
      }),
    };

    await initWhatsAppEmbeddedSignup('config-123');

    expect(EMBEDDED_SIGNUP_EXTRAS.version).toBe('v4');
  });

  it('rejects when the popup is closed without a code', async () => {
    window.FB = { login: vi.fn(callback => callback({})) };

    await expect(initWhatsAppEmbeddedSignup('config-123')).rejects.toThrow(
      'Login cancelled'
    );
  });
});

describe('isValidBusinessData', () => {
  it('accepts a coexistence completion that carries only waba_id', () => {
    expect(isValidBusinessData({ waba_id: '111' })).toBe(true);
  });

  it('rejects a payload without waba_id', () => {
    expect(isValidBusinessData({ business_id: '222' })).toBe(false);
    expect(isValidBusinessData(undefined)).toBe(false);
  });
});

describe('classifySignupEvent', () => {
  it('reads a new-number FINISH as a non-coexistence finish', () => {
    const event = signupEvent('FINISH', {
      phone_number_id: '1',
      waba_id: '2',
      business_id: '3',
    });

    expect(classifySignupEvent(event)).toEqual({
      type: SIGNUP_RESULT.FINISH,
      isCoexistence: false,
    });
  });

  it('reads the business-app onboarding finish as coexistence', () => {
    const event = signupEvent('FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', {
      waba_id: '2',
    });

    expect(classifySignupEvent(event)).toEqual({
      type: SIGNUP_RESULT.FINISH,
      isCoexistence: true,
    });
  });

  it.each(['FINISH_ONLY_WABA', 'FINISH_GRANT_ONLY_API_ACCESS'])(
    'reports %s as a completion with no number to connect',
    name => {
      expect(classifySignupEvent(signupEvent(name, { waba_id: '2' }))).toEqual({
        type: SIGNUP_RESULT.UNSUPPORTED,
      });
    }
  );

  it('reads the v4 ERROR event, whose message sits inside data', () => {
    const event = signupEvent('ERROR', {
      error_message: 'Number already in use',
      error_code: '524126',
      session_id: 's',
    });

    expect(classifySignupEvent(event)).toEqual({
      type: SIGNUP_RESULT.ERROR,
      errorMessage: 'Number already in use',
    });
  });

  it('still reads the older lowercase error with a top-level message', () => {
    const event = { ...signupEvent('error'), error_message: 'Old shape' };

    expect(classifySignupEvent(event)).toEqual({
      type: SIGNUP_RESULT.ERROR,
      errorMessage: 'Old shape',
    });
  });

  it('tells a dismissal apart from a CANCEL that carries an error', () => {
    expect(
      classifySignupEvent(
        signupEvent('CANCEL', { current_step: 'PHONE_NUMBER_SETUP' })
      )
    ).toEqual({ type: SIGNUP_RESULT.CANCEL });

    expect(
      classifySignupEvent(signupEvent('CANCEL', { error_message: 'Blocked' }))
    ).toEqual({ type: SIGNUP_RESULT.ERROR, errorMessage: 'Blocked' });
  });

  it('ignores payloads without an event name', () => {
    expect(classifySignupEvent({ type: 'WA_EMBEDDED_SIGNUP' })).toEqual({
      type: SIGNUP_RESULT.IGNORE,
    });
    expect(classifySignupEvent(null)).toEqual({ type: SIGNUP_RESULT.IGNORE });
  });
});
