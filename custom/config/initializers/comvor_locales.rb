# frozen_string_literal: true

# Comvor: the custom/ strings (custom/config/locales), loaded after the app's
# own so config/locales stays as upstream.
Rails.application.config.i18n.load_path += Dir[Rails.root.join('custom/config/locales/**/*.yml')]
