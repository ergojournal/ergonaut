class AddWaiverToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :waiver, :boolean
  end
end
