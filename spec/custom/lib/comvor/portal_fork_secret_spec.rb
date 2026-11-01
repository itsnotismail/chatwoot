# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Comvor::PortalFork do
  describe '.secret_matches?' do
    let(:secret) { 'a-shared-secret-of-some-length' }

    around { |example| with_modified_env(PORTAL_FORK_SHARED_SECRET: secret) { example.run } }

    it 'is true only for the secret itself' do
      expect(described_class.secret_matches?(secret)).to be true
      [secret.upcase, "#{secret} ", secret[0..-2], "#{secret}x", '', 'x', nil, 5, [secret], { a: secret }].each do |other|
        expect(described_class.secret_matches?(other)).to be(false), other.inspect
      end
    end

    it 'is never true while no secret is set, not even for an empty one' do
      ['', nil].each do |unset|
        with_modified_env(PORTAL_FORK_SHARED_SECRET: unset) do
          expect(described_class.secret_matches?('')).to be false
          expect(described_class.secret_matches?(secret)).to be false
        end
      end
    end

    it 'compares digests, so the lengths of the two secrets never differ' do
      allow(ActiveSupport::SecurityUtils).to receive(:secure_compare).and_call_original

      described_class.secret_matches?('x')

      expect(ActiveSupport::SecurityUtils).to have_received(:secure_compare) { |a, b| expect([a.bytesize, b.bytesize]).to eq([64, 64]) }
    end
  end
end
