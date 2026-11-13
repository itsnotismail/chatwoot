require 'rails_helper'

# /.well-known/assetlinks.json keeps upstream's statement and adds one for
# Comvor Agent with every fingerprint COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS
# lists (Comvor::AndroidAssetLinks).
RSpec.describe 'GET /.well-known/assetlinks.json (Comvor)', type: :request do
  let(:upload_key) { Array.new(32) { 'AB' }.join(':') }
  let(:play_key) { Array.new(32) { '0F' }.join(':') }
  let(:official) { Array.new(32) { 'AC' }.join(':') }

  def statements
    get '/.well-known/assetlinks.json'
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  def target_for(package)
    statements.map { |statement| statement['target'] }.find { |target| target['package_name'] == package }
  end

  it 'keeps upstream\'s statement for ANDROID_BUNDLE_ID, and adds nothing while no Comvor Agent fingerprint is set' do
    with_modified_env(ANDROID_BUNDLE_ID: 'com.chatwoot.app', ANDROID_SHA256_CERT_FINGERPRINT: official,
                      COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS: nil) do
      expect(statements).to eq([{ 'relation' => ['delegate_permission/common.handle_all_urls'],
                                  'target' => { 'namespace' => 'android_app', 'package_name' => 'com.chatwoot.app',
                                                'sha256_cert_fingerprints' => [official] } }])
    end
  end

  it 'lists every Comvor Agent fingerprint for com.comvor.agent, alongside the official app' do
    with_modified_env(ANDROID_BUNDLE_ID: 'com.chatwoot.app', ANDROID_SHA256_CERT_FINGERPRINT: official,
                      COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS: "#{upload_key}, #{play_key.downcase} ,") do
      expect(target_for('com.chatwoot.app')['sha256_cert_fingerprints']).to eq([official])
      expect(target_for('com.comvor.agent')).to eq('namespace' => 'android_app', 'package_name' => 'com.comvor.agent',
                                                   'sha256_cert_fingerprints' => [upload_key, play_key])
    end
  end

  it 'leaves out a value that is not a SHA-256 fingerprint, and duplicates' do
    with_modified_env(COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS: "not-a-key,#{upload_key},AB:CD,#{upload_key}") do
      expect(target_for('com.comvor.agent')['sha256_cert_fingerprints']).to eq([upload_key])
    end
  end

  it 'adds no Comvor Agent statement when every value is invalid' do
    with_modified_env(COMVOR_AGENT_ANDROID_SHA256_CERT_FINGERPRINTS: 'not-a-key') do
      expect(target_for('com.comvor.agent')).to be_nil
    end
  end
end
