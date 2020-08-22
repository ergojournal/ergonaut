class AddDonorCodeToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :donor_code, :string
  end
end
