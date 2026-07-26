/**
 * Comvor: installation-name branding for translated copy.
 *
 * Upstream Chatwoot hardcodes "Chatwoot" in ~27 English UI strings (settings,
 * inbox setup, audit logs, help center, …) and ships
 * shared/composables/useBranding.js to swap it for the installation name — but
 * never calls it from anywhere. These helpers wire that mechanism into the
 * vue-i18n layer so the replacement happens once, for every string and every
 * locale, instead of being hardcoded per file.
 *
 * Doing it at render time rather than by editing the locale JSON matters for
 * two reasons: the ~30 non-English locales carry the same strings and are
 * community-managed (the repo's CLAUDE.md says to only ever edit en.json), and
 * a hardcoded fork of upstream copy would conflict on every upstream merge.
 */

/**
 * Replaces "Chatwoot" in text with installationName.
 *
 * Case-sensitive on purpose, matching useBranding's long-standing behaviour:
 * it leaves lowercase occurrences alone, which is what keeps genuine
 * chatwoot.com URLs in help text (help-center slug examples, the DNS CNAME
 * instructions) pointing at real hosts instead of being rewritten into
 * addresses that do not exist.
 *
 * @param {string} text
 * @param {string} installationName
 * @returns {string}
 */
export function replaceInstallationName(text, installationName) {
  if (!text || !installationName) return text;

  return text.replace(/Chatwoot/g, installationName);
}

/**
 * vue-i18n `postTranslation` hook: brands every resolved message.
 *
 * Reads window.globalConfig, which the Rails layout writes before any bundle
 * runs (app/views/layouts/vueapp.html.erb), rather than the Vuex store — the
 * hook fires outside component setup, so composables are unavailable, and the
 * store is not necessarily hydrated on first paint.
 *
 * Non-string messages (vue-i18n resolves some message types to other shapes)
 * pass through untouched, and a missing globalConfig degrades to the original
 * text rather than throwing — this runs on every single translation, so it
 * must never be able to break rendering.
 *
 * @param {unknown} translated
 * @returns {unknown}
 */
export function brandedPostTranslation(translated) {
  if (typeof translated !== 'string') return translated;

  return replaceInstallationName(
    translated,
    typeof window === 'undefined'
      ? undefined
      : window.globalConfig?.INSTALLATION_NAME
  );
}
