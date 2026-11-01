# frozen_string_literal: true

# Asks comvor-api whether a second-factor code (a TOTP code or a recovery
# code; the portal tries both) is good for this portal user
# (POST /portal/api/v1/internal/fork/verify-totp). Only {"ok":true} is.
class Comvor::PortalTotpVerifier
  PATH = '/portal/api/v1/internal/fork/verify-totp'

  pattr_initialize [:email!, :code!, :client_ip]

  def perform
    answer = Comvor::PortalFork.post(PATH, { email: email, code: code }, client_ip: client_ip)
    answer.present? && answer['ok'] == true
  end
end
