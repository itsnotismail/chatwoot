# frozen_string_literal: true

# Only an account's administrators read or change its SAML settings.
class Comvor::SamlSettingPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end
