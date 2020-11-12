require "rails_helper"

RSpec.describe Seed::Runner do
  let(:config) { Seed::Config.new }

  it "creates expected number of records from fast seed config" do
    facilities = create_list(:facility, 2, facility_size: "community")
    facilities.each do |f|
      create(:user, registration_facility: f, role: ENV["SEED_GENERATED_ACTIVE_USER_ROLE"])
    end

    expected_bps = config.max_bps_to_create * config.max_patients_to_create.fetch(:community) * facilities.size
    seeder = Seed::Runner.new
    expect {
      seeder.call
    }.to change { Patient.count }.by(6)
      .and change { PatientBusinessIdentifier.count }.by(6)
      .and change { MedicalHistory.count }.by(6)
      .and change { BloodPressure.count }.by(expected_bps)
      .and change { Encounter.count }.by(expected_bps)
      .and change { Observation.count }.by(expected_bps)
  end

  it "returns how many records are created per facility and total" do
    facilities = create_list(:facility, 2, facility_size: "community")
    facilities.each do |f|
      create(:user, registration_facility: f, role: ENV["SEED_GENERATED_ACTIVE_USER_ROLE"])
    end

    expected_bps = config.max_bps_to_create * config.max_patients_to_create.fetch(:community)
    seeder = Seed::Runner.new
    result = seeder.call
    facilities.each { |f| expect(f.patients.size).to eq(3) }
    facilities.pluck(:slug).each do |slug|
      expect(result[slug][:patient]).to eq(3)
      expect(result[slug][:blood_pressure]).to eq(expected_bps)
      expect(result[slug][:observation]).to eq(expected_bps)
      expect(result[slug][:encounter]).to eq(expected_bps)
      expect(result[slug][:appointment]).to eq(3)
    end
    expect(result[:total][:facility]).to eq(0)
    expect(result[:total][:patient]).to eq(6)
    expect(result[:total][:blood_pressure]).to eq(90)
    expect(result[:total][:observation]).to eq(90)
    expect(result[:total][:encounter]).to eq(90)
  end

  it "can create a fast data set in under 10 seconds" do
    time = Benchmark.ms {
      seeder = Seed::Runner.new
      seeder.call
    }
    time_in_seconds = time / 1000
    puts "#{time_in_seconds} seconds"
    expect(time_in_seconds).to be < 10
  end
end