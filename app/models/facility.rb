require "roo"

class Facility < ApplicationRecord
  include Mergeable
  include QuarterHelper
  include PgSearch::Model
  include LiberalEnum
  extend FriendlyId
  extend RegionSource

  attribute :import, :boolean, default: false
  attribute :organization_name, :string
  attribute :facility_group_name, :string

  belongs_to :facility_group, optional: true

  has_many :phone_number_authentications, foreign_key: "registration_facility_id"
  has_many :users, through: :phone_number_authentications
  has_and_belongs_to_many :teleconsultation_medical_officers,
    -> { distinct },
    class_name: "User",
    association_foreign_key: :user_id,
    join_table: "facilities_teleconsultation_medical_officers"

  has_many :encounters
  has_many :blood_pressures, through: :encounters, source: :blood_pressures
  has_many :blood_sugars, through: :encounters, source: :blood_sugars
  has_many :patients, -> { distinct }, through: :encounters
  has_many :prescription_drugs
  has_many :appointments
  has_many :teleconsultations

  has_many :registered_patients,
    class_name: "Patient",
    foreign_key: "registration_facility_id"
  has_many :registered_diabetes_patients,
    -> { with_diabetes },
    class_name: "Patient",
    foreign_key: "registration_facility_id"
  has_many :registered_hypertension_patients,
    -> { with_hypertension },
    class_name: "Patient",
    foreign_key: "registration_facility_id"
  has_many :assigned_patients,
    class_name: "Patient",
    foreign_key: "assigned_facility_id"
  has_many :assigned_hypertension_patients,
    -> { with_hypertension },
    class_name: "Patient",
    foreign_key: "assigned_facility_id"

  pg_search_scope :search_by_name, against: {name: "A", slug: "B"}, using: {tsearch: {prefix: true, any_word: true}}

  enum facility_size: {
    community: "community",
    small: "small",
    medium: "medium",
    large: "large"
  }

  liberal_enum :facility_size

  auto_strip_attributes :name, squish: true, upcase_first: true
  auto_strip_attributes :district, squish: true, upcase_first: true
  auto_strip_attributes :zone, squish: true, upcase_first: true

  with_options if: :import do |facility|
    facility.validates :organization_name, presence: true
    facility.validates :facility_group_name, presence: true
    facility.validate :facility_name_presence
    facility.validate :organization_exists
    facility.validate :facility_group_exists
    facility.validate :facility_is_unique
  end

  with_options unless: :import do |facility|
    facility.validates :name, presence: true
  end

  alias_attribute :block, :zone

  validates :district, presence: true
  validates :state, presence: true
  validates :country, presence: true
  validates :zone, presence: true, on: :create
  validates :pin, numericality: true, allow_blank: true

  validates :facility_size, inclusion: {in: facility_sizes.values,
                                        message: "not in #{facility_sizes.values.join(", ")}",
                                        allow_blank: true}
  validates :enable_teleconsultation, inclusion: {in: [true, false]}
  validates :teleconsultation_medical_officers,
    presence: {
      if: :enable_teleconsultation,
      message: "must be added to enable teleconsultation"
    }

  validates :enable_diabetes_management, inclusion: {in: [true, false]}

  delegate :protocol, to: :facility_group, allow_nil: true
  delegate :organization, :organization_id, to: :facility_group, allow_nil: true
  delegate :follow_ups_by_period, to: :patients, prefix: :patient

  def hypertension_follow_ups_by_period(*args)
    patients
      .hypertension_follow_ups_by_period(*args)
      .where(blood_pressures: {facility: self})
  end

  def diabetes_follow_ups_by_period(*args)
    patients
      .diabetes_follow_ups_by_period(*args)
      .where(blood_sugars: {facility: self})
  end

  friendly_id :name, use: :slugged

  # For compatibility w/ parent FacilityGroups
  def facilities
    [self]
  end

  def recent_blood_pressures
    blood_pressures.includes(:patient, :user).order(Arel.sql("DATE(recorded_at) DESC, recorded_at ASC"))
  end

  def cohort_analytics(period:, prev_periods:)
    query = CohortAnalyticsQuery.new(self, period: period, prev_periods: prev_periods)
    query.call
  end

  def dashboard_analytics(period: :month, prev_periods: 3, include_current_period: false)
    query = FacilityAnalyticsQuery.new(self, period, prev_periods, include_current_period: include_current_period)
    query.call
  end

  CSV_IMPORT_COLUMNS = {
    organization_name: "organization",
    facility_group_name: "facility_group",
    name: "facility_name",
    facility_type: "facility_type",
    street_address: "street_address (optional)",
    village_or_colony: "village_or_colony (optional)",
    zone: "zone_or_block",
    district: "district",
    state: "state",
    country: "country",
    pin: "pin (optional)",
    latitude: "latitude (optional)",
    longitude: "longitude (optional)",
    facility_size: "size (optional)",
    enable_diabetes_management: "enable_diabetes_management (true/false)"
  }

  def self.parse_facilities(file_contents)
    facilities = []
    CSV.parse(file_contents, headers: true, converters: :strip_whitespace) do |row|
      facility = CSV_IMPORT_COLUMNS.map { |attribute, column_name| [attribute, row[column_name]] }.to_h
      next if facility.values.all?(&:blank?)

      facilities << facility.merge(enable_diabetes_management: facility[:enable_diabetes_management] || false,
                                   enable_teleconsultation: facility[:enable_teleconsultation] || false,
                                   import: true)
    end
    facilities
  end

  def organization_exists
    organization = Organization.find_by(name: organization_name)
    errors.add(:organization, "doesn't exist") if organization_name.present? && organization.blank?
  end

  def facility_group_exists
    organization = Organization.find_by(name: organization_name)
    if organization.present?
      facility_group = FacilityGroup.find_by(name: facility_group_name,
                                             organization_id: organization.id)
    end
    if organization.present? && facility_group_name.present? && facility_group.blank?
      errors.add(:facility_group, "doesn't exist for the organization")
    end
  end

  def facility_is_unique
    organization = Organization.find_by(name: organization_name)
    if organization.present?
      facility_group = FacilityGroup.find_by(name: facility_group_name,
                                             organization_id: organization.id)
    end
    facility = Facility.find_by(name: name, facility_group: facility_group.id) if facility_group.present?
    errors.add(:facility, "already exists") if organization.present? && facility_group.present? && facility.present?
  end

  def facility_name_presence
    if name.blank?
      errors.add(:facility_name, "can't be blank")
    end
  end

  def diabetes_enabled?
    enable_diabetes_management.present?
  end

  def opd_load_estimated?
    monthly_estimated_opd_load.present?
  end

  def opd_load
    monthly_estimated_opd_load || opd_load_for_facility_size
  end

  def opd_load_for_facility_size
    case facility_size
    when "community" then 450
    when "small" then 1800
    when "medium" then 3000
    when "large" then 7500
    else 450
    end
  end

  def teleconsultation_enabled?
    enable_teleconsultation.present?
  end

  def teleconsultation_phone_number_with_isd
    teleconsultation_phone_numbers_with_isd.first
  end

  def teleconsultation_phone_numbers_with_isd
    teleconsultation_medical_officers.map(&:full_teleconsultation_phone_number)
  end

  CSV::Converters[:strip_whitespace] = ->(value) {
    begin
      value.strip
    rescue
      value
    end
  }

  def discardable?
    registered_patients.none? && blood_pressures.none? && blood_sugars.none? && appointments.none?
  end
end
