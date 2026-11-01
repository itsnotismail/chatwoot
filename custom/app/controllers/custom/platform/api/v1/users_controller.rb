# frozen_string_literal: true

# Refuses a password on a Platform API update of an existing saml user.
# Create stays as upstream: comvor-api provisions users with a password,
# and create never assigns one to a user that already exists.
module Custom::Platform::Api::V1::UsersController
  def update
    if params[:password].present? && Comvor::SamlPasswordGuard.saml?(@resource)
      return render json: { error: Comvor::SamlPasswordGuard.refusal }, status: :forbidden
    end

    super
  end
end
