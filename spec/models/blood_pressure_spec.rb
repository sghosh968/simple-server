require "rails_helper"

RSpec.describe BloodPressure, type: :model do
  describe "Validations" do
    it_behaves_like "a record that validates device timestamps"
  end

  describe "Associations" do
    it { should belong_to(:facility).optional }
    it { should belong_to(:patient).optional }
    it { should belong_to(:user).optional }
  end

  describe "Behavior" do
    it_behaves_like "a record that is deletable"
  end

  describe "Scopes" do
    describe ".hypertensive" do
      it "only includes hypertensive BPs" do
        bp_normal = create(:blood_pressure, systolic: 120, diastolic: 80)
        bp_high_systolic = create(:blood_pressure, systolic: 140, diastolic: 80)
        bp_high_diastolic = create(:blood_pressure, systolic: 120, diastolic: 90)
        bp_high_both = create(:blood_pressure, systolic: 150, diastolic: 100)

        expect(BloodPressure.hypertensive).to include(bp_high_systolic, bp_high_diastolic, bp_high_both)
        expect(BloodPressure.hypertensive).not_to include(bp_normal)
      end
    end

    describe ".under_control" do
      it "only includes BPs under control" do
        bp_normal = create(:blood_pressure, systolic: 120, diastolic: 80)
        bp_high_systolic = create(:blood_pressure, systolic: 140, diastolic: 80)
        bp_high_diastolic = create(:blood_pressure, systolic: 120, diastolic: 90)
        bp_high_both = create(:blood_pressure, systolic: 150, diastolic: 100)

        expect(BloodPressure.under_control).to include(bp_normal)
        expect(BloodPressure.under_control).not_to include(bp_high_systolic, bp_high_diastolic, bp_high_both)
      end
    end

    describe ".syncable_to_region" do
      it "returns all patients registered in the region" do
        facility_group = create(:facility_group)
        facility = create(:facility, facility_group: facility_group)
        patient = create(:patient)
        other_patient = create(:patient)

        allow(Patient).to receive(:syncable_to_region).with(facility_group).and_return([patient])

        blood_pressures = [
          create(:blood_pressure, patient: patient, facility: facility),
          create(:blood_pressure, patient: patient, facility: facility).tap(&:discard),
          create(:blood_pressure, patient: patient)
        ]

        _other_blood_pressures = [
          create(:blood_pressure, patient: other_patient, facility: facility),
          create(:blood_pressure, patient: other_patient, facility: facility).tap(&:discard),
          create(:blood_pressure, patient: other_patient)
        ]

        expect(BloodPressure.syncable_to_region(facility_group)).to contain_exactly(*blood_pressures)
      end
    end
  end

  context "utility methods" do
    let(:bp_normal) { create(:blood_pressure, systolic: 120, diastolic: 80) }
    let(:bp_high_systolic) { create(:blood_pressure, systolic: 140, diastolic: 80) }
    let(:bp_high_diastolic) { create(:blood_pressure, systolic: 120, diastolic: 90) }
    let(:bp_high_both) { create(:blood_pressure, systolic: 150, diastolic: 100) }

    describe "#under_control?" do
      it "returns true if both systolic and diastolic are under control" do
        expect(bp_normal).to be_under_control
      end

      it "returns false if systolic is high" do
        expect(bp_high_systolic).not_to be_under_control
      end

      it "returns false if diastolic is high" do
        expect(bp_high_diastolic).not_to be_under_control
      end

      it "returns false if both systolic and diastolic are high" do
        expect(bp_high_both).not_to be_under_control
      end
    end

    describe "#critical?" do
      [{systolic: 181, diastolic: 111},
        {systolic: 181, diastolic: 109},
        {systolic: 179, diastolic: 111}].each do |row|
        it "returns true if bp is in a critical state" do
          bp = create(:blood_pressure, systolic: row[:systolic], diastolic: row[:diastolic])
          expect(bp).to be_critical
        end
      end

      it "returns false if bp is not in a critical state" do
        bp = create(:blood_pressure, systolic: 179, diastolic: 109)
        expect(bp).not_to be_critical
      end
    end

    describe "#hypertensive?" do
      [{systolic: 140, diastolic: 80},
        {systolic: 120, diastolic: 90},
        {systolic: 180, diastolic: 120}].each do |row|
        it "returns true if bp is high" do
          bp = create(:blood_pressure, systolic: row[:systolic], diastolic: row[:diastolic])
          expect(bp).to be_hypertensive
        end
      end

      it "returns false if bp is not high" do
        bp = create(:blood_pressure, systolic: 139, diastolic: 89)
        expect(bp).not_to be_hypertensive
      end
    end

    describe "#recorded_days_ago" do
      it "returns 2 days" do
        bp_recorded_2_days_ago = create(:blood_pressure, device_created_at: 2.days.ago)

        expect(bp_recorded_2_days_ago.recorded_days_ago).to eq(2)
      end
    end

    describe "#to_s" do
      it "is systolic/diastolic" do
        expect(bp_normal.to_s).to eq("120/80")
      end
    end
  end

  context "anonymised data for blood pressures" do
    describe "anonymized_data" do
      it "correctly retrieves the anonymised data for the blood pressure" do
        blood_pressure = create(:blood_pressure)

        anonymised_data =
          {id: Hashable.hash_uuid(blood_pressure.id),
           patient_id: Hashable.hash_uuid(blood_pressure.patient_id),
           created_at: blood_pressure.created_at,
           bp_date: blood_pressure.recorded_at,
           registration_facility_name: blood_pressure.facility.name,
           user_id: Hashable.hash_uuid(blood_pressure.user.id),
           bp_systolic: blood_pressure.systolic,
           bp_diastolic: blood_pressure.diastolic}

        expect(blood_pressure.anonymized_data).to eq anonymised_data
      end
    end
  end

  context "#find_or_update_observation!" do
    let(:blood_pressure) { create(:blood_pressure, :with_encounter) }
    let!(:encounter) { blood_pressure.encounter }
    let!(:observation) { blood_pressure.observation }
    let!(:user) { blood_pressure.user }

    it "updates discarded observations also" do
      observation.discard
      blood_pressure.reload

      encounter.encountered_on = 1.year.ago
      encounter.save
      blood_pressure.find_or_update_observation!(encounter, user)

      expect(encounter.encountered_on).to eq 1.year.ago.to_date
    end
  end
end
