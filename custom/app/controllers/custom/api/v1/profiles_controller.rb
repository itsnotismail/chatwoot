# frozen_string_literal: true

# Refuses a password change from the profile page for a saml user.
module Custom::Api::V1::ProfilesController
  def update
    if params.dig(:profile, :password).present? && Comvor::SamlPasswordGuard.saml?(current_user)
      return render json: { error: Comvor::SamlPasswordGuard.refusal }, status: :forbidden
    end

    super
  end
end
