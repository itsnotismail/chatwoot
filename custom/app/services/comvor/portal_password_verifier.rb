# frozen_string_literal: true

# Asks comvor-api whether an email and password sign in to the portal
# (POST /portal/api/v1/internal/fork/verify-password). Its only answers are
# {"ok":false,"totp_required":false} and ok:true with or without a second
# factor owed; anything else is :rejected.
class Comvor::PortalPasswordVerifier
  PATH = '/portal/api/v1/internal/fork/verify-password'

  pattr_initialize [:email!, :password!, :client_ip]

  def self.enabled?
    Comvor::PortalFork.enabled?
  end

  # :ok, :totp_required or :rejected.
  def perform
    answer = Comvor::PortalFork.post(PATH, { email: email, password: password }, client_ip: client_ip)
    return :rejected unless answer && answer['ok'] == true

    answer['totp_required'] == true ? :totp_required : :ok
  end
end
