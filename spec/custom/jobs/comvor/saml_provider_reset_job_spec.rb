require 'rails_helper'

# DELETE /saml_settings is the rollback lever: the account's users go back to
# password sign-in. Mirrors the reset half of
# spec/enterprise/jobs/saml/update_account_users_provider_job_spec.rb.
RSpec.describe Comvor::SamlProviderResetJob do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:saml_user) { create(:user, account: account, provider: 'saml') }
  let!(:google_user) { create(:user, account: account, provider: 'google') }

  def sso_on(for_account)
    Comvor::SamlSetting.new(account: for_account).save!(validate: false)
  end

  it "updates all of the account's users to the email provider" do
    described_class.perform_now(account.id)

    expect(saml_user.reload.provider).to eq('email')
    expect(google_user.reload.provider).to eq('email')
  end

  it 'preserves SAML for a user who is a member of another account with SAML settings' do
    sso_on(other_account)
    create(:account_user, account: other_account, user: saml_user)

    described_class.perform_now(account.id)

    expect(saml_user.reload.provider).to eq('saml')
    expect(google_user.reload.provider).to eq('email')
  end

  it 'resets a user whose other account has no SAML settings' do
    create(:account_user, account: other_account, user: saml_user)

    described_class.perform_now(account.id)

    expect(saml_user.reload.provider).to eq('email')
  end

  it 'leaves users of other accounts alone' do
    outsider = create(:user, account: other_account, provider: 'saml')

    described_class.perform_now(account.id)

    expect(outsider.reload.provider).to eq('saml')
  end

  it 'does nothing when the account has SAML settings again by the time it runs' do
    sso_on(account)

    described_class.perform_now(account.id)

    expect(saml_user.reload.provider).to eq('saml')
  end

  it 'does nothing for an account that no longer exists' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
