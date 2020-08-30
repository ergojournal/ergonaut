class AddWaiverTypeToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :waiver_type, :string
  end
end
