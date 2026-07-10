class IndexRefereeAssignmentsOnSubmission < ActiveRecord::Migration
  # referee_assignments (17k+ rows) had no index on submission_id, so the
  # externally_reviewed / not_externally_reviewed EXISTS subqueries used by the
  # statistics page full-scanned the whole table for every submission in the
  # window (~27s, timing out the last_12_months view). Index the FK so those
  # become index lookups.
  def change
    add_index :referee_assignments, [:submission_id, :report_completed],
              name: "index_ra_submission_id_report_completed"
  end
end
