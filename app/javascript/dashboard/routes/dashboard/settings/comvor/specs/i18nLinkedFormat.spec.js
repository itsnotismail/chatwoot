import comvorMessages from 'dashboard/i18n/locale/en/comvorSettings.json';

// vue-i18n treats a bare "@" as its linked-message operator (e.g. "@:key"),
// and THROWS "Invalid linked format" when it compiles a message containing an
// unescaped "@" (like "@userinfobot"). At runtime that crashes the component
// rendering the string — e.g. adding a Telegram channel blanked the whole
// notifications editor. A literal "@" must be escaped as {'@'}. This guard
// walks every comvor translation and fails if any bare "@" survives.
function leafStrings(obj, path = []) {
  return Object.entries(obj).flatMap(([key, value]) => {
    const next = [...path, key];
    if (typeof value === 'string') return [[next.join('.'), value]];
    if (value && typeof value === 'object') return leafStrings(value, next);
    return [];
  });
}

describe('comvor i18n — no unescaped @ (vue-i18n linked-format footgun)', () => {
  it("every translation escapes literal @ as {'@'}", () => {
    const offenders = leafStrings(comvorMessages)
      .filter(([, value]) => value.replace(/\{'@'\}/g, '').includes('@'))
      .map(([key, value]) => `${key}: ${value}`);

    expect(offenders).toEqual([]);
  });
});
