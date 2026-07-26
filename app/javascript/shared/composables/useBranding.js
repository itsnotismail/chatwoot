/**
 * Composable for branding-related utilities
 * Provides methods to customize text with installation-specific branding
 */
import { useMapGetter } from 'dashboard/composables/store.js';
import { replaceInstallationName as brandText } from 'shared/helpers/branding';

export function useBranding() {
  const globalConfig = useMapGetter('globalConfig/get');
  /**
   * Replaces "Chatwoot" in text with the installation name from global config
   * @param {string} text - The text to process
   * @returns {string} - Text with "Chatwoot" replaced by installation name
   */
  const replaceInstallationName = text =>
    // Comvor: the substitution itself lives in shared/helpers/branding so this
    // composable and the vue-i18n postTranslation hook cannot drift apart on
    // what counts as a brand mention. This wrapper only supplies the source of
    // the installation name — the store, which is correct inside a component.
    brandText(text, globalConfig.value?.installationName);

  return {
    replaceInstallationName,
  };
}
