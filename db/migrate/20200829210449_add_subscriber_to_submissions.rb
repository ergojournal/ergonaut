class AddSubscriberToSubmissions < ActiveRecord::Migration
  def change
    add_column :submissions, :subscriber, :string
  end
end
