require "rails_helper"

RSpec.describe FacilityGroup, type: :model do
  describe "Associations" do
    it { should belong_to(:organization) }
    it { should have_many(:facilities) }

    it { have_many(:patients).through(:facilities) }
    it { have_many(:assigned_patients).through(:facilities).source(:assigned_patients) }
    it { have_many(:blood_pressures).through(:facilities) }
    it { have_many(:blood_sugars).through(:facilities) }
    it { have_many(:prescription_drugs).through(:facilities) }
    it { have_many(:appointments).through(:facilities) }
    it { have_many(:teleconsultations).through(:facilities) }
    it { have_many(:medical_histories).through(:patients) }
    it { have_many(:communications).through(:appointments) }

    it { belong_to(:protocol) }

    it "nullifies facility_group_id in facilities" do
      facility_group = FactoryBot.create(:facility_group)
      FactoryBot.create_list(:facility, 5, facility_group: facility_group)
      expect { facility_group.destroy }.not_to change { Facility.count }
      expect(Facility.where(facility_group: facility_group)).to be_empty
    end
  end

  context "Validations" do
    it { should validate_presence_of(:name) }
  end

  context "Behavior" do
    it_behaves_like "a record that is deletable"
  end

  context "slugs" do
    it "generates slug on creation and avoids conflicts via appending a UUID" do
      fg_1 = create(:facility_group, name: "New York")
      expect(fg_1.slug).to eq("new-york")
      fg_2 = create(:facility_group, name: "New York")
      uuid_regex = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/
      expect(fg_2.slug).to match(/^new-york-#{uuid_regex}$/)
    end

    it "does not change the slug when renamed" do
      facility_group = create(:facility_group, name: "old_name")
      original_slug = facility_group.slug
      facility_group.name = "new name"
      facility_group.valid?
      facility_group.save!
      expect(facility_group.slug).to eq(original_slug)
    end
  end

  describe "Attribute sanitization" do
    it "squishes and upcases the first letter of the name" do
      facility_group = FactoryBot.create(:facility_group, name: "facility  Group  ")
      expect(facility_group.name).to eq("Facility Group")
    end
  end

  describe "#toggle_diabetes_management" do
    let!(:facility_group) { create(:facility_group) }
    let!(:facilities) { create_list(:facility, 2, facility_group: facility_group) }
    before { facility_group.reload }

    context "when enable_diabetes_management is set to true" do
      before { facility_group.enable_diabetes_management = true }

      it "enables diabetes management for all facilities" do
        facility_group.facilities.update(enable_diabetes_management: false)
        facility_group.toggle_diabetes_management
        expect(Facility.pluck(:enable_diabetes_management)).to all be true
      end
    end

    context "when enable_diabetes_management is set to false" do
      before { facility_group.enable_diabetes_management = false }

      it "disables diabetes management for all facilities if it is enabled for all facilities" do
        facility_group.facilities.update(enable_diabetes_management: true)
        facility_group.toggle_diabetes_management
        expect(Facility.pluck(:enable_diabetes_management)).to all be false
      end

      it "does not disable diabetes management for all facilities if it is enabled for some facilities" do
        facilities.first.update(enable_diabetes_management: true)
        facilities.second.update(enable_diabetes_management: false)
        facility_group.toggle_diabetes_management

        expect(Facility.pluck(:enable_diabetes_management)).to match_array [true, false]
      end
    end
  end

  describe ".discardable?" do
    let!(:facility_group) { create(:facility_group) }

    context "isn't discardable if data exists" do
      it "has patients" do
        facility = create(:facility, facility_group: facility_group)
        create(:patient, registration_facility: facility)

        expect(facility_group.discardable?).to be false
      end

      it "has appointments" do
        facility = create(:facility, facility_group: facility_group)
        create(:appointment, facility: facility)

        expect(facility_group.discardable?).to be false
      end

      it "has facilities" do
        create(:facility, facility_group: facility_group)

        expect(facility_group.discardable?).to be false
      end

      it "has blood pressures" do
        facility = create(:facility, facility_group: facility_group)
        blood_pressure = create(:blood_pressure, facility: facility)
        create(:encounter, :with_observables, observable: blood_pressure)

        expect(facility_group.discardable?).to be false
      end

      it "has blood sugars" do
        facility = create(:facility, facility_group: facility_group)
        blood_sugar = create(:blood_sugar, facility: facility)
        create(:encounter, :with_observables, observable: blood_sugar)

        expect(facility_group.discardable?).to be false
      end
    end

    context "is discardable if no data exists" do
      it "has no data" do
        expect(facility_group.discardable?).to be true
      end
    end
  end

  describe "Callbacks" do
    context "when regions_prep is enabled" do
      before do
        enable_flag(:regions_prep)
      end

      context "after_create" do
        let!(:org) { create(:organization, name: "IHCI") }
        let!(:facility_group) { create(:facility_group, name: "FG", state: "Punjab", organization: org) }

        it "creates a region" do
          expect(facility_group.region).to be_present
          expect(facility_group.region).to be_persisted
          expect(facility_group.region.name).to eq "FG"
          expect(facility_group.region.path).to eq "india.ihci.punjab.fg"
        end

        it "creates the state region if it doesn't exist" do
          expect(facility_group.region.state_region.name).to eq "Punjab"
        end
      end

      context "after_update" do
        let!(:org) { create(:organization, name: "IHCI") }
        let!(:facility_group) { create(:facility_group, name: "FG", state: "Punjab", organization: org) }

        it "updates the associated region" do
          facility_group.update(name: "New FG name")
          expect(facility_group.region.name).to eq "New FG name"
          expect(facility_group.region.path).to eq "india.ihci.punjab.fg"
        end

        it "updates the state region" do
          facility_group.update(state: "Maharashtra")
          expect(facility_group.region.state_region.name).to eq "Maharashtra"
          expect(facility_group.region.path).to eq "india.ihci.maharashtra.fg"
        end
      end
    end
  end
end
