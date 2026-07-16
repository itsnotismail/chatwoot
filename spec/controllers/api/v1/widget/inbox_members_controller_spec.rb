require 'rails_helper'

RSpec.describe '/api/v1/widget/inbox_members', type: :request do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }
  let(:agent_1) { create(:user, account: account) }
  let(:agent_2) { create(:user, account: account) }

  before do
    create(:inbox_member, user: agent_1, inbox: web_widget.inbox)
    create(:inbox_member, user: agent_2, inbox: web_widget.inbox)
  end

  describe 'GET /api/v1/widget/inbox_members' do
    let(:params) { { website_token: web_widget.website_token } }

    context 'with correct website token' do
      it 'returns the list of agents' do
        get '/api/v1/widget/inbox_members', params: params

        expect(response).to have_http_status(:success)
        json_response = response.parsed_body
        expect(json_response['payload'].length).to eq 2
      end
    end

    context 'with invalid website token' do
      it 'returns the list of agents' do
        get '/api/v1/widget/inbox_members', params: { website_token: '' }
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when an active agent bot is attached to the inbox' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before { create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, status: :active) }

      it 'surfaces the bot as an online agent so the widget is not shown as away' do
        get '/api/v1/widget/inbox_members', params: params

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.length).to eq 3 # two human agents + the bot

        bot_entry = payload.find { |a| a['id'] == "agent-bot-#{agent_bot.id}" }
        expect(bot_entry).to be_present
        expect(bot_entry['availability_status']).to eq 'online'
        expect(bot_entry['name']).to eq agent_bot.available_name
      end
    end

    context 'when the attached agent bot is inactive' do
      let(:agent_bot) { create(:agent_bot, account: account) }

      before { create(:agent_bot_inbox, inbox: web_widget.inbox, agent_bot: agent_bot, status: :inactive) }

      it 'does not surface the bot as an online agent' do
        get '/api/v1/widget/inbox_members', params: params

        expect(response).to have_http_status(:success)
        payload = response.parsed_body['payload']
        expect(payload.length).to eq 2 # only the two human agents
        expect(payload.any? { |a| a['id'].to_s.start_with?('agent-bot-') }).to be false
      end
    end
  end
end
