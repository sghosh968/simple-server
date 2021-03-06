require "rails_helper"

RSpec.describe Api::V3::FacilityTransformer do
  describe ".to_response" do
    let(:facility) { FactoryBot.build(:facility) }

    it "sets the sync_region_id to the facility group id" do
      transformed_facility = Api::V3::FacilityTransformer.to_response(facility)
      expect(transformed_facility[:sync_region_id]).to eq facility.facility_group_id
    end
  end
end
