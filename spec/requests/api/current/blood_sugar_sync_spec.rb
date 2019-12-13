require 'rails_helper'

RSpec.describe 'BloodSugars sync', type: :request do
  let(:sync_route) { '/api/v3/blood_sugars/sync' }
  let(:request_user) { FactoryBot.create(:user) }

  let(:model) { BloodSugar }

  let(:build_payload) { lambda { build_blood_sugar_payload(FactoryBot.build(:blood_sugar, facility: request_user.facility)) } }
  let(:build_invalid_payload) { lambda { build_invalid_blood_sugar_payload } }
  let(:update_payload) { lambda { |blood_sugar| updated_blood_sugar_payload blood_sugar } }

  def to_response(blood_sugar)
    Api::Current::Transformer.to_response(blood_sugar)
  end

  include_examples 'current API sync requests'
end