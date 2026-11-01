# frozen_string_literal: true

module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    # Not saml_settings: enterprise's concern defines that name.
    has_one :comvor_saml_setting, -> { order(:id) }, class_name: 'Comvor::SamlSetting', inverse_of: :account, dependent: :destroy_async
  end
end
