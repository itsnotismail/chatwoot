import { replaceInstallationName, brandedPostTranslation } from '../branding';

describe('replaceInstallationName', () => {
  it('replaces every occurrence', () => {
    expect(
      replaceInstallationName('Chatwoot syncs to Chatwoot', 'Comvor')
    ).toBe('Comvor syncs to Comvor');
  });

  it('returns the text untouched when there is no installation name', () => {
    expect(replaceInstallationName('Welcome to Chatwoot', undefined)).toBe(
      'Welcome to Chatwoot'
    );
    expect(replaceInstallationName('Welcome to Chatwoot', '')).toBe(
      'Welcome to Chatwoot'
    );
  });

  it('handles empty and nullish text', () => {
    expect(replaceInstallationName('', 'Comvor')).toBe('');
    expect(replaceInstallationName(null, 'Comvor')).toBe(null);
    expect(replaceInstallationName(undefined, 'Comvor')).toBe(undefined);
  });

  // Load-bearing: help-center slug examples and the DNS CNAME instructions
  // contain real chatwoot.com hostnames. Rewriting those would point users at
  // addresses that do not exist.
  it('leaves lowercase chatwoot.com URLs alone', () => {
    expect(
      replaceInstallationName(
        'Chatwoot serves app.chatwoot.com/hc/my-portal',
        'Comvor'
      )
    ).toBe('Comvor serves app.chatwoot.com/hc/my-portal');
  });
});

describe('brandedPostTranslation', () => {
  const originalConfig = window.globalConfig;

  afterEach(() => {
    window.globalConfig = originalConfig;
  });

  it('brands a translated string from window.globalConfig', () => {
    window.globalConfig = { INSTALLATION_NAME: 'Comvor' };

    expect(brandedPostTranslation('Welcome to Chatwoot')).toBe(
      'Welcome to Comvor'
    );
  });

  it('passes non-string messages through untouched', () => {
    window.globalConfig = { INSTALLATION_NAME: 'Comvor' };

    const list = ['a', 'b'];
    expect(brandedPostTranslation(list)).toBe(list);
    expect(brandedPostTranslation(42)).toBe(42);
    expect(brandedPostTranslation(undefined)).toBe(undefined);
  });

  // This hook runs on EVERY translation, so a missing or half-built
  // globalConfig must degrade to the original text rather than throw and take
  // rendering down with it.
  it('degrades to the original text when globalConfig is absent', () => {
    window.globalConfig = undefined;
    expect(brandedPostTranslation('Welcome to Chatwoot')).toBe(
      'Welcome to Chatwoot'
    );

    window.globalConfig = {};
    expect(brandedPostTranslation('Welcome to Chatwoot')).toBe(
      'Welcome to Chatwoot'
    );
  });
});

// Integration guard: proves the hook is wired the way the entrypoints wire it
// and that this vue-i18n version actually applies it. A wrong option name here
// would fail silently — every string would simply render unbranded — and no
// unit test of the helper alone would catch it.
describe('brandedPostTranslation wired into createI18n', () => {
  const originalConfig = window.globalConfig;

  afterEach(() => {
    window.globalConfig = originalConfig;
  });

  it('brands messages resolved through $t', async () => {
    window.globalConfig = { INSTALLATION_NAME: 'Comvor' };
    const { createI18n } = await import('vue-i18n');

    const i18n = createI18n({
      legacy: false,
      locale: 'en',
      messages: {
        en: { NOTE: 'Customize the look and feel of your Chatwoot dashboard.' },
      },
      postTranslation: brandedPostTranslation,
    });

    expect(i18n.global.t('NOTE')).toBe(
      'Customize the look and feel of your Comvor dashboard.'
    );
  });
});
