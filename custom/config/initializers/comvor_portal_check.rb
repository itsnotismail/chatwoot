# frozen_string_literal: true

# Comvor: say at boot when production's portal address is plain HTTP
# (Comvor::PortalIdp.warn_if_insecure), rather than leave it a silent outage.
Rails.application.config.after_initialize { Comvor::PortalIdp.warn_if_insecure }
