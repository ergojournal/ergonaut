class AddFeeSystemToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :fee_system, :boolean
  end
end
