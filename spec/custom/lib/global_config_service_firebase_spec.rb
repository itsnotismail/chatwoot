require 'rails_helper'

# Pins the runbook facts in custom/docs/push-dual-run.md: where
# GlobalConfigService.load gets FIREBASE_* from, and why removing them from
# the deploy env neither switches direct FCM on nor rolls it back on its own.
RSpec.describe GlobalConfigService do
  before { GlobalConfig.clear_cache }
  after { GlobalConfig.clear_cache }

  it 'copies the env value into an InstallationConfig row when no row exists, so it outlives the env var' do
    with_modified_env FIREBASE_PROJECT_ID: 'from-env' do
      expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to eq('from-env')
    end
    expect(InstallationConfig.find_by(name: 'FIREBASE_PROJECT_ID')&.value).to eq('from-env')

    GlobalConfig.clear_cache
    with_modified_env FIREBASE_PROJECT_ID: nil do
      expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to eq('from-env')
    end
  end

  it 'ignores the env value when ConfigLoader has already seeded an empty row (what db:migrate does)' do
    ConfigLoader.new.process
    expect(InstallationConfig.find_by(name: 'FIREBASE_PROJECT_ID')).to be_present
    GlobalConfig.clear_cache

    with_modified_env FIREBASE_PROJECT_ID: 'from-env' do
      expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to be_nil
    end
  end

  it 'returns a blank string when the row was blanked in Super Admin and the env var is still set' do
    InstallationConfig.create!(name: 'FIREBASE_PROJECT_ID', value: '', locked: false)
    GlobalConfig.clear_cache

    with_modified_env FIREBASE_PROJECT_ID: 'from-env' do
      expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to eq('')
    end
  end

  it 'switches off once the row value is cleared, with the env var gone' do
    InstallationConfig.create!(name: 'FIREBASE_PROJECT_ID', value: 'set-in-super-admin', locked: false)
    expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to eq('set-in-super-admin')

    InstallationConfig.find_by(name: 'FIREBASE_PROJECT_ID').update!(value: nil)
    GlobalConfig.clear_cache
    with_modified_env FIREBASE_PROJECT_ID: nil do
      expect(described_class.load('FIREBASE_PROJECT_ID', nil)).to be_nil
    end
  end
end
