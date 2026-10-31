# frozen_string_literal: true

require 'rails_helper'

# Comvor: the seat cap the Platform API sets in accounts.limits is what refuses an agent added straight
# through the Application API, past the portal's own seat check.
RSpec.describe 'Agents API seat limit', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { admin }

  it 'refuses an agent past limits.agents with 402' do
    account.update!(limits: { 'agents' => 2 })
    create(:user, account: account, role: :agent)

    post "/api/v1/accounts/#{account.id}/agents",
         params: { name: 'Third', email: Faker::Internet.email, role: :agent },
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:payment_required)
    expect(account.users.count).to eq(2)
  end

  it 'adds an agent while under limits.agents' do
    account.update!(limits: { 'agents' => 2 })

    post "/api/v1/accounts/#{account.id}/agents",
         params: { name: 'Second', email: Faker::Internet.email, role: :agent },
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:success)
  end
end
