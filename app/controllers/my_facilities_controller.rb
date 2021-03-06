# frozen_string_literal: true

class MyFacilitiesController < AdminController
  include Pagination
  include MyFacilitiesFiltering
  include CohortPeriodSelection
  include PeriodSelection

  DEFAULT_ANALYTICS_TIME_ZONE = "Asia/Kolkata"
  PERIODS_TO_DISPLAY = {quarter: 3, month: 3, day: 14}.freeze

  around_action :set_time_zone
  before_action :authorize_my_facilities
  before_action :set_selected_cohort_period, only: [:blood_pressure_control]
  before_action :set_selected_period, only: [:registrations, :missed_visits]
  before_action :set_last_updated_at

  def index
    @facilities = current_admin.accessible_facilities(:view_reports)
    users = current_admin.accessible_users(:manage)

    @users_requesting_approval = paginate(users
                                            .requested_sync_approval
                                            .order(updated_at: :desc))

    overview_query = MyFacilities::OverviewQuery.new(facilities: @facilities)
    @inactive_facilities = overview_query.inactive_facilities

    @facility_counts_by_size = {total: @facilities.group(:facility_size).count,
                                inactive: @inactive_facilities.group(:facility_size).count}

    @inactive_facilities_bp_counts =
      {last_week: overview_query.total_bps_in_last_n_days(n: 7),
       last_month: overview_query.total_bps_in_last_n_days(n: 30)}
  end

  def blood_pressure_control
    @facilities = filter_facilities([:manage, :facility])

    bp_query = MyFacilities::BloodPressureControlQuery.new(facilities: @facilities,
                                                           cohort_period: @selected_cohort_period)

    @totals = {cohort_patients: bp_query.cohort_patients.count,
               controlled: bp_query.cohort_controlled_bps.count,
               uncontrolled: bp_query.cohort_uncontrolled_bps.count,
               missed: bp_query.cohort_missed_visits_count,
               overall_patients: bp_query.overall_patients.count,
               overall_controlled_bps: bp_query.overall_controlled_bps.count}

    @cohort_patients_per_facility = bp_query.cohort_patients_per_facility
    @controlled_bps_per_facility = bp_query.cohort_controlled_bps_per_facility
    @uncontrolled_bps_per_facility = bp_query.cohort_uncontrolled_bps_per_facility
    @missed_visits_by_facility = bp_query.cohort_missed_visits_count_by_facility
    @overall_patients_per_facility = bp_query.overall_patients_per_facility
    @overall_controlled_bps_per_facility = bp_query.overall_controlled_bps_per_facility
  end

  def registrations
    @facilities = filter_facilities([:manage, :facility])

    registrations_query = MyFacilities::RegistrationsQuery.new(facilities: @facilities,
                                                               period: @selected_period,
                                                               last_n: PERIODS_TO_DISPLAY[@selected_period])

    @registrations = registrations_query.registrations
      .group(:facility_id, :year, @selected_period)
      .sum(:registration_count)

    @total_registrations = registrations_query.total_registrations_per_facility
    @total_registrations_by_period =
      @registrations.each_with_object({}) { |(key, registrations), total_registrations_by_period|
        period = [key.second.to_i, key.third.to_i]
        total_registrations_by_period[period] ||= 0
        total_registrations_by_period[period] += registrations
      }
    @display_periods = registrations_query.periods
  end

  def missed_visits
    @facilities = filter_facilities([:manage, :facility])

    missed_visits_query = MyFacilities::MissedVisitsQuery.new(facilities: @facilities,
                                                              period: @selected_period,
                                                              last_n: PERIODS_TO_DISPLAY[@selected_period])

    @display_periods = missed_visits_query.periods
    @missed_visits_by_facility = missed_visits_query.missed_visits_by_facility
    @calls_made = missed_visits_query.calls_made.count
    @total_patients_per_facility = missed_visits_query.total_patients_per_facility
    @totals_by_period = missed_visits_query.missed_visit_totals
  end

  private

  def set_last_updated_at
    last_updated_at = RefreshMaterializedViews.last_updated_at
    @last_updated_at =
      if last_updated_at.nil?
        "unknown"
      else
        last_updated_at.in_time_zone(Rails.application.config.country[:time_zone]).strftime("%d-%^b-%Y %I:%M%p")
      end
  end

  def set_time_zone
    time_zone = Rails.application.config.country[:time_zone] || DEFAULT_ANALYTICS_TIME_ZONE

    Time.use_zone(time_zone) { yield }
  end

  def authorize_my_facilities
    authorize { current_admin.accessible_facilities(:view_reports).any? }
  end
end
