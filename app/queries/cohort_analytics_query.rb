class CohortAnalyticsQuery
  include QuarterHelper

  def initialize(patients, period = :month)
    @patients = patients
    @period = period
  end

  def patient_counts_by_period(prev_periods: 6)
    results = {}

    (0..(prev_periods)).each do |periods_back|
      if @period == :month
        cohort_start = (Time.now - periods_back.months).beginning_of_month
        cohort_end   = cohort_start.end_of_month
        report_start = (cohort_start + 1.month).beginning_of_month
        report_end   = (cohort_end + 1.month).end_of_month
      else
        cohort_start = (Time.now - (3 * periods_back.months)).beginning_of_quarter
        cohort_end   = cohort_start.end_of_quarter
        report_start = (cohort_start + 3.months).beginning_of_quarter
        report_end   = (cohort_end + 3.months).end_of_quarter
      end

      results[[cohort_start, report_start]] = patient_counts(cohort_start, cohort_end, report_start, report_end)
    end

    results
  end

  def patient_counts(cohort_start, cohort_end, report_start, report_end)
    registered_patients = registered(cohort_start, cohort_end)
    followed_up_patients = followed_up(registered_patients, report_start, report_end)
    controlled_patients = controlled(followed_up_patients)
    uncontrolled_patients = followed_up_patients - controlled_patients

    {
      registered: registered_patients.size,
      followed_up: followed_up_patients.size,
      defaulted: registered_patients.size - followed_up_patients.size,
      controlled: controlled_patients.size,
      uncontrolled: uncontrolled_patients.size
    }
  end

  def registered(cohort_start, cohort_end)
    @patients.where(recorded_at: cohort_start..cohort_end)
  end

  def followed_up(registered_patients, report_start, report_end)
    registered_patients.select(%Q(
      patients.*,
      newest_bps.recorded_at as bp_recorded_at,
      newest_bps.systolic as bp_systolic,
      newest_bps.diastolic as bp_diastolic
    )).joins(%Q(
      INNER JOIN (
        SELECT DISTINCT ON (patient_id) *
        FROM blood_pressures
        WHERE recorded_at >= '#{report_start}'
        AND recorded_at <= '#{report_end}'
        ORDER BY patient_id, recorded_at DESC
      ) as newest_bps
      ON newest_bps.patient_id = patients.id
    ))
  end

  def controlled(patients)
    patients.select { |p| p.bp_systolic < 140 && p.bp_diastolic < 90 }
  end
end
