# frozen_string_literal: true

# The user a portal SAML sign-in for an account signs in as, matched by the
# asserted email:
# - an existing user must already be a member of that account, or sign-in is
#   refused (the portal vouches for an email, not for a membership);
# - an existing member becomes a SAML user, confirmed; one who was not
#   confirmed also gets a random password, as the community OAuth callback
#   does, so whoever signed up with that email cannot keep using theirs;
# - an unknown email becomes a new confirmed SAML user and a member of the
#   account, as an agent unless the settings' role_mappings say otherwise.
#   Staff first reach the workspace this way, so a new member also joins
#   every inbox and gets push alerts for new conversations and for new
#   messages in their assigned ones. Only then: an owner who later removes
#   someone from an inbox is not overridden.
class Comvor::SamlUserBuilder
  class AuthenticationFailed < StandardError
    def initialize(msg = I18n.t('auth.saml.authentication_failed'))
      super
    end
  end

  PROVIDER = 'saml'
  ROLES = %w[agent administrator].freeze
  NEW_MEMBER_PUSH_FLAGS = %i[push_conversation_creation push_assigned_conversation_new_message].freeze

  def initialize(email:, account_id:, name: nil, first_name: nil, groups: [])
    @email = email.to_s.strip.downcase
    @account = Account.find_by(id: account_id) || raise(AuthenticationFailed)
    @name = name
    @first_name = first_name
    @groups = Array(groups).map(&:to_s)
  end

  def perform
    raise AuthenticationFailed if @email.blank?

    user = User.from_email(@email)
    user ? convert_member(user) : create_member
  end

  private

  def convert_member(user)
    raise AuthenticationFailed unless user.account_users.exists?(account_id: @account.id)

    user.provider = PROVIDER
    unless user.confirmed?
      user.skip_confirmation!
      user.password = random_password
    end
    user.save! if user.changed?
    user
  end

  def create_member
    user = ActiveRecord::Base.transaction do
      User.create!(email: @email, name: @name.presence || @email.split('@').first, display_name: @first_name.presence,
                   provider: PROVIDER, password: random_password, confirmed_at: Time.current).tap do |created|
        AccountUser.create!(account: @account, user: created, **mapped_role)
      end
    end
    join_every_inbox(user)
    turn_on_push_alerts(user)
    user
  end

  def mapped_role
    mappings = Comvor::SamlSetting.for_account(@account.id)&.role_mappings.presence || {}
    group = @groups.find { |name| mappings.key?(name) }
    return { role: :agent } if group.nil?

    mapping = mappings[group].to_h
    { role: mapped_role_name(mapping['role']), custom_role_id: mapping['custom_role_id'] }.compact
  end

  # A role name or its enum value; anything else is an agent.
  def mapped_role_name(value)
    name = value.is_a?(Integer) || value.to_s.match?(/\A\d+\z/) ? AccountUser.roles.key(value.to_i) : value.to_s
    ROLES.include?(name) ? name : 'agent'
  end

  # Meets the password rules (upper, lower, digit, symbol), as the community
  # OAuth callback's random password does.
  def random_password
    "#{SecureRandom.hex(16)}aA1!"
  end

  def join_every_inbox(user)
    missing = @account.inboxes.where.not(id: user.inbox_members.select(:inbox_id))
    return if missing.none?

    missing.each { |inbox| InboxMember.create!(inbox: inbox, user: user) }
    @account.update_cache_key('inbox')
  end

  # The account's notification setting is created when the membership commits.
  def turn_on_push_alerts(user)
    setting = user.notification_settings.find_by!(account_id: @account.id)
    setting.selected_push_flags = (setting.selected_push_flags + NEW_MEMBER_PUSH_FLAGS).uniq
    setting.save!
  end
end
