require 'rails_helper'

# Comvor: the reauthorization writes the WABA id (not the business portfolio id) and keeps a
# phone_number_id when a coexistence completion omits it. Shape ported from upstream #15462.
describe Whatsapp::ReauthorizationService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+9601111111', provider: 'whatsapp_cloud',
                              provider_config: { 'phone_number_id' => 'old_phone_id', 'business_account_id' => 'old_waba' },
                              validate_provider_config: false, sync_templates: false)
  end
  let(:phone_info) { { phone_number_id: 'meta_phone_id', phone_number: '+9601111111', business_name: 'Shop' } }

  before do
    # Saving provider_config re-syncs templates and creating the channel sets up its webhook.
    stub_request(:any, /graph.facebook.com/).to_return(status: 200, body: '{"data": []}', headers: { 'Content-Type' => 'application/json' })
    channel.prompt_reauthorization!
  end

  def reauthorize(phone_number_id:)
    described_class.new(account: account, inbox_id: channel.inbox.id, phone_number_id: phone_number_id, waba_id: 'new_waba')
                   .perform('new_token', phone_info)
  end

  it 'stores the WABA id as business_account_id' do
    reauthorize(phone_number_id: 'event_phone_id')

    expect(channel.reload.provider_config).to include(
      'business_account_id' => 'new_waba', 'phone_number_id' => 'event_phone_id', 'source' => 'embedded_signup'
    )
    expect(channel.reauthorization_required?).to be false
  end

  it 'falls back to the phone_number_id Meta returned when the signup event omitted it' do
    reauthorize(phone_number_id: '')

    expect(channel.reload.provider_config['phone_number_id']).to eq('meta_phone_id')
  end

  it 'refuses a different number' do
    phone_info[:phone_number] = '+9602222222'

    expect { reauthorize(phone_number_id: nil) }.to raise_error(/Phone number mismatch/)
  end
end
