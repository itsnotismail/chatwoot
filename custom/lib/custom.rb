# frozen_string_literal: true

# Namespace prepend_mod_with looks up Custom::<Class> in. Defined here so the
# lookup works before any Custom:: module exists.
module Custom; end
