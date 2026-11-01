require 'rails_helper'

# Ported from spec/enterprise/builders/saml_user_builder_spec.rb (today's
# enterprise SAML builder, Comvor's examples included), with the assertions
# kept, against Comvor's own builder.
RSpec.describe Comvor::SamlUserBuilder do
  let(:email) { 'saml.user@example.com' }
  let(:account) { create(:account) }
  let(:groups) { %w[Administrators Users] }
  let(:builder) { described_class.new(email: email, account_id: account.id, name: 'SAML User', first_name: 'SAML', groups: groups) }

  def saml_setting(role_mappings)
    Comvor::SamlSetting.new(account: account, role_mappings: role_mappings).save!(validate: false)
  end

  def refused
    yield
  rescue described_class::AuthenticationFailed
    nil
  end

  describe '#perform' do
    context 'when user does not exist' do
      it 'creates a new user' do
        expect { builder.perform }.to change(User, :count).by(1)
      end

      it 'creates user with correct attributes' do
        user = builder.perform

        expect(user.email).to eq(email)
        expect(user.name).to eq('SAML User')
        expect(user.display_name).to eq('SAML')
        expect(user.provider).to eq('saml')
        expect(user.uid).to eq(email)
        expect(user.confirmed_at).to be_present
      end

      it 'creates user with a random password' do
        expect(builder.perform.encrypted_password).to be_present
      end

      it 'adds user to the account' do
        expect(builder.perform.accounts).to include(account)
      end

      it 'sets default role as agent' do
        user = builder.perform
        expect(AccountUser.find_by(user: user, account: account).role).to eq('agent')
      end

      it 'matches the email whatever its case' do
        user = described_class.new(email: ' Saml.User@Example.com ', account_id: account.id).perform
        expect(user.email).to eq(email)
      end

      context 'when name is not provided' do
        let(:builder) { described_class.new(email: email, account_id: account.id) }

        it 'derives name from email' do
          expect(builder.perform.name).to eq('saml.user')
        end
      end
    end

    context 'when a new team member signs in for the first time' do
      let!(:facebook_inbox) { create(:inbox, account: account) }
      let!(:website_inbox) { create(:inbox, account: account) }

      it 'adds them to every inbox of the account' do
        user = builder.perform
        expect(facebook_inbox.reload.members).to include(user)
        expect(website_inbox.reload.members).to include(user)
      end

      it 'turns on push alerts for new conversations and new messages in assigned conversations' do
        user = builder.perform
        setting = user.notification_settings.find_by(account_id: account.id)
        expect(setting.push_conversation_creation?).to be(true)
        expect(setting.push_assigned_conversation_new_message?).to be(true)
        expect(setting.push_conversation_assignment?).to be(true)
      end
    end

    context 'when an existing team member signs in again' do
      let!(:inbox) { create(:inbox, account: account) }

      it 'does not re-add them to an inbox the owner removed them from' do
        user = builder.perform
        InboxMember.where(user: user, inbox: inbox).destroy_all

        described_class.new(email: email, account_id: account.id).perform
        expect(inbox.reload.members).not_to include(user)
      end
    end

    context 'when user already exists' do
      let!(:existing_user) { create(:user, email: email, account: account) }

      it 'does not create a new user' do
        expect { builder.perform }.not_to change(User, :count)
      end

      it 'returns the existing user' do
        expect(builder.perform).to eq(existing_user)
      end

      it 'keeps the existing user in the account' do
        expect(builder.perform.accounts).to include(account)
      end

      it 'converts existing user to SAML' do
        expect(existing_user.provider).not_to eq('saml')

        builder.perform

        expect(existing_user.reload.provider).to eq('saml')
      end

      it 'does not change provider if user is already SAML' do
        existing_user.update!(provider: 'saml')

        expect { builder.perform }.not_to(change { existing_user.reload.provider })
      end

      it 'does not duplicate account association' do
        expect { builder.perform }.not_to change(AccountUser, :count)
      end

      it 'does not add them to inboxes or change their alerts' do
        inbox = create(:inbox, account: account)
        setting = existing_user.notification_settings.find_by(account_id: account.id)

        expect { builder.perform }.not_to(change { setting.reload.push_flags })
        expect(inbox.reload.members).not_to include(existing_user)
      end

      context 'when the user does not belong to the target account' do
        let!(:other_account) { create(:account) }
        let!(:existing_user) { create(:user, email: email, account: other_account) }

        it 'raises an authentication failure' do
          expect { builder.perform }.to raise_error do |error|
            expect(error.class.name).to eq('Comvor::SamlUserBuilder::AuthenticationFailed')
            expect(error.message).to eq(I18n.t('auth.saml.authentication_failed'))
          end
        end

        it 'does not add the user to the target account' do
          expect { refused { builder.perform } }.not_to change(AccountUser, :count)
          expect(existing_user.reload.accounts).not_to include(account)
        end

        it 'does not convert the user provider to saml' do
          expect { refused { builder.perform } }.not_to(change { existing_user.reload.provider })
        end
      end

      context 'when user is not confirmed' do
        let!(:existing_user) do
          user = build(:user, email: email, account: account)
          user.confirmed_at = nil
          user.save!(validate: false)
          user
        end

        it 'confirms unconfirmed user after SAML authentication' do
          expect(existing_user.confirmed?).to be false

          builder.perform

          expect(existing_user.reload.confirmed?).to be true
        end
      end

      context 'when user is already confirmed' do
        let!(:existing_user) { create(:user, email: email, account: account, confirmed_at: Time.current) }

        it 'keeps already confirmed user confirmed' do
          original_confirmed_at = existing_user.confirmed_at

          builder.perform

          expect(existing_user.reload.confirmed?).to be true
          expect(existing_user.reload.confirmed_at).to be_within(2.seconds).of(original_confirmed_at)
        end
      end
    end

    context 'with role mappings' do
      before { saml_setting('Administrators' => { 'role' => 'administrator' }, 'Agents' => { 'role' => 'agent' }) }

      it 'applies administrator role based on SAML groups' do
        user = builder.perform
        expect(AccountUser.find_by(user: user, account: account).role).to eq('administrator')
      end

      context 'with custom role mapping' do
        # A plain id: custom roles are an enterprise model, and the column
        # exists in both editions.
        before { Comvor::SamlSetting.where(account: account).update_all(role_mappings: { 'Administrators' => { 'custom_role_id' => 42 } }) } # rubocop:disable Rails/SkipsModelValidations

        it 'applies custom role based on SAML groups' do
          user = builder.perform
          expect(AccountUser.find_by(user: user, account: account).custom_role_id).to eq(42)
        end
      end

      context 'when user is not in any mapped groups' do
        let(:groups) { ['UnmappedGroup'] }

        it 'keeps default agent role' do
          user = builder.perform
          expect(AccountUser.find_by(user: user, account: account).role).to eq('agent')
        end
      end
    end

    context 'when the account no longer exists' do
      it 'refuses' do
        expect { described_class.new(email: email, account_id: 0).perform }.to raise_error(described_class::AuthenticationFailed)
      end
    end

    context 'when user creation fails' do
      it 'creates neither the user nor the membership' do
        allow(AccountUser).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

        expect { builder.perform }.to raise_error(ActiveRecord::RecordInvalid)
        expect(User.from_email(email)).to be_nil
      end
    end
  end
end
