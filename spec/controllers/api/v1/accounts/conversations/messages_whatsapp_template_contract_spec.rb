require 'rails_helper'

# Pins how a bot-created message with template_params ends up on the WhatsApp Cloud API, and how failures surface.
# The provider is stubbed; the path runs through the real controller, builder, SendReplyJob and bot webhook listener.
RSpec.describe 'WhatsApp template send contract for agent bots', type: :request do
  let(:account) { create(:account) }
  let(:agent_bot) { create(:agent_bot, account: account, outgoing_url: 'https://bot.example.com/webhook') }
  let(:templates) do
    [
      { 'name' => 'order_shipped', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'en_US', 'parameter_format' => 'POSITIONAL',
        'components' => [
          { 'type' => 'BODY', 'text' => 'Hi {{1}}, order {{2}} has shipped.' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'text' => 'Track', 'url' => 'https://t.example.com/{{1}}' }] }
        ] },
      { 'name' => 'payment_reminder', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'en', 'parameter_format' => 'NAMED',
        'components' => [{ 'type' => 'BODY', 'text' => 'Hello {{customer_name}}' }] },
      { 'name' => 'promo_code', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'en', 'parameter_format' => 'POSITIONAL',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Offer for {{1}}' },
          { 'type' => 'BODY', 'text' => 'Use this code on order {{1}}.' },
          { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'SAVE10' }] }
        ] },
      { 'name' => 'invoice_ready', 'status' => 'APPROVED', 'category' => 'UTILITY', 'language' => 'en', 'parameter_format' => 'POSITIONAL',
        'components' => [
          { 'type' => 'HEADER', 'format' => 'DOCUMENT' },
          { 'type' => 'BODY', 'text' => 'Invoice {{1}} is attached.' }
        ] },
      { 'name' => 'rejected_offer', 'status' => 'REJECTED', 'category' => 'MARKETING', 'language' => 'en',
        'components' => [{ 'type' => 'BODY', 'text' => 'Offer {{1}}' }] }
    ]
  end
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, sync_templates: false, validate_provider_config: false,
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '9607771234') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox) }
  let(:messages_url) { "https://graph.facebook.com/v13.0/#{channel.provider_config['phone_number_id']}/messages" }
  let(:bot_payloads) { [] }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: agent_bot)
    allow(AgentBots::WebhookJob).to receive(:perform_later) { |_url, payload, *| bot_payloads << payload }
  end

  def create_bot_message(params)
    post "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}/messages",
         params: params, headers: { api_access_token: agent_bot.access_token.token }, as: :json
    expect(response).to have_http_status(:ok)
    Message.find(response.parsed_body['id'])
  end

  def template_request_body(name, language, components)
    {
      messaging_product: 'whatsapp', recipient_type: 'individual', to: '9607771234', type: 'template',
      template: { name: name, language: { policy: 'deterministic', code: language }, components: components }
    }.to_json
  end

  def failed_update_payload(message)
    bot_payloads.find { |payload| payload[:event] == 'message_updated' && payload[:id] == message.id && payload[:status] == 'failed' }
  end

  it 'sends an approved positional template outside the window with body and button parameters' do
    stub = stub_request(:post, messages_url)
           .with(body: template_request_body('order_shipped', 'en_US', [
                                               { type: 'body', parameters: [{ type: 'text', text: 'Aisha' }, { type: 'text', text: 'A-17' }] },
                                               { type: 'button', sub_type: 'url', index: 0, parameters: [{ type: 'text', text: 'A-17' }] }
                                             ]))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.OK1' }] }.to_json, headers: { 'content-type' => 'application/json' })

    message = create_bot_message(
      content: 'Hi Aisha, order A-17 has shipped.',
      template_params: {
        name: 'order_shipped', language: 'en_US', category: 'UTILITY',
        processed_params: { body: { '1' => 'Aisha', '2' => 'A-17' }, buttons: [{ type: 'url', parameter: 'A-17' }] }
      }
    )
    expect(message.additional_attributes['template_params']['name']).to eq('order_shipped')
    expect(conversation.can_reply?).to be(false)

    SendReplyJob.perform_now(message.id)

    expect(stub).to have_been_requested.once
    expect(message.reload.source_id).to eq('wamid.OK1')
    expect(message.status).to eq('sent')
  end

  it 'sends named body parameters for a NAMED template' do
    stub = stub_request(:post, messages_url)
           .with(body: template_request_body('payment_reminder', 'en', [
                                               { type: 'body', parameters: [{ type: 'text', parameter_name: 'customer_name', text: 'Aisha' }] }
                                             ]))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.OK2' }] }.to_json, headers: { 'content-type' => 'application/json' })

    message = create_bot_message(content: 'Hello Aisha',
                                 template_params: { name: 'payment_reminder', language: 'en', category: 'UTILITY',
                                                    processed_params: { body: { customer_name: 'Aisha' } } })
    SendReplyJob.perform_now(message.id)

    expect(stub).to have_been_requested.once
    expect(message.reload.source_id).to eq('wamid.OK2')
  end

  it 'sends a text header, body and copy_code button in header, body, button order' do
    stub = stub_request(:post, messages_url)
           .with(body: template_request_body('promo_code', 'en', [
                                               { type: 'header', parameters: [{ type: 'text', text: 'Aisha' }] },
                                               { type: 'body', parameters: [{ type: 'text', text: 'A-17' }] },
                                               { type: 'button', sub_type: 'copy_code', index: 0,
                                                 parameters: [{ type: 'coupon_code', coupon_code: 'SAVE10' }] }
                                             ]))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.OK4' }] }.to_json, headers: { 'content-type' => 'application/json' })

    message = create_bot_message(
      content: 'Offer for Aisha',
      template_params: { name: 'promo_code', language: 'en',
                         processed_params: { header: { '1' => 'Aisha' }, body: { '1' => 'A-17' },
                                             buttons: [{ type: 'copy_code', parameter: 'SAVE10' }] } }
    )
    SendReplyJob.perform_now(message.id)

    expect(stub).to have_been_requested.once
    expect(message.reload.source_id).to eq('wamid.OK4')
  end

  it 'sends a media header as a document link with its filename' do
    stub = stub_request(:post, messages_url)
           .with(body: template_request_body('invoice_ready', 'en', [
                                               { type: 'header', parameters: [{ type: 'document',
                                                                                document: { link: 'https://cdn.example.com/inv-17.pdf',
                                                                                            filename: 'inv-17.pdf' } }] },
                                               { type: 'body', parameters: [{ type: 'text', text: 'INV-17' }] }
                                             ]))
           .to_return(status: 200, body: { messages: [{ id: 'wamid.OK5' }] }.to_json, headers: { 'content-type' => 'application/json' })

    message = create_bot_message(
      content: 'Invoice INV-17 is attached.',
      template_params: { name: 'invoice_ready', language: 'en',
                         processed_params: { header: { media_url: 'https://cdn.example.com/inv-17.pdf', media_type: 'document',
                                                       media_name: 'inv-17.pdf' },
                                             body: { '1' => 'INV-17' } } }
    )
    SendReplyJob.perform_now(message.id)

    expect(stub).to have_been_requested.once
    expect(message.reload.source_id).to eq('wamid.OK5')
  end

  it 'sends a template even inside the window when template_params are present' do
    create(:message, message_type: :incoming, conversation: conversation, account: account, inbox: inbox)
    stub = stub_request(:post, messages_url).with(body: hash_including('type' => 'template'))
                                            .to_return(status: 200, body: { messages: [{ id: 'wamid.OK3' }] }.to_json,
                                                       headers: { 'content-type' => 'application/json' })

    reminder = { name: 'payment_reminder', language: 'en', processed_params: { body: { customer_name: 'Aisha' } } }
    message = create_bot_message(content: 'Hello Aisha', template_params: reminder)
    SendReplyJob.perform_now(message.id)

    expect(stub).to have_been_requested.once
  end

  [
    ['an unknown template name', 'no_such_template', 'en'],
    ['a rejected template', 'rejected_offer', 'en'],
    ['an approved template in a language that was not synced', 'order_shipped', 'dv']
  ].each do |label, name, language|
    it "still calls the provider for #{label}, with the parameters dropped, and fails the message only from the provider error" do
      stub = stub_request(:post, messages_url)
             .with(body: template_request_body(name, language, []))
             .to_return(status: 400, headers: { 'content-type' => 'application/json' },
                        body: { error: { message: '(#132001) Template name does not exist in the translation', code: 132_001 } }.to_json)

      message = create_bot_message(content: 'x', template_params: { name: name, language: language, processed_params: { body: { '1' => 'A-17' } } })
      SendReplyJob.perform_now(message.id)

      expect(stub).to have_been_requested.once
      expect(message.reload.status).to eq('failed')
      expect(message.external_error).to eq('(#132001) Template name does not exist in the translation')
      payload = failed_update_payload(message)
      expect(payload).to be_present
      expect(payload[:content_attributes][:external_error]).to eq('(#132001) Template name does not exist in the translation')
    end
  end

  it 'fails a plain reply outside the window without calling the provider, and tells the bot' do
    stub = stub_request(:post, messages_url)

    message = create_bot_message(content: 'Your order is ready')
    SendReplyJob.perform_now(message.id)

    expect(stub).not_to have_been_requested
    expect(message.reload.status).to eq('failed')
    expect(message.external_error).to eq('Template not found or invalid template name')
    expect(failed_update_payload(message)[:content_attributes][:external_error]).to eq('Template not found or invalid template name')
  end

  it 'leaves the message sent, with no source_id and no failure, when the provider errors without an error message' do
    stub_request(:post, messages_url).to_return(status: 500, body: '', headers: { 'content-type' => 'application/json' })

    message = create_bot_message(content: 'x', template_params: { name: 'payment_reminder', language: 'en',
                                                                  processed_params: { body: { customer_name: 'Aisha' } } })
    SendReplyJob.perform_now(message.id)

    expect(message.reload.status).to eq('sent')
    expect(message.source_id).to be_nil
    expect(message.external_error).to be_nil
    expect(failed_update_payload(message)).to be_nil
  end
end
