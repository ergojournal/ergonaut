class CreateAreaEditorAssignments < ActiveRecord::Migration
  def change
    create_table :area_editor_assignments do |t|
      t.integer :user_id
      t.integer :submission_id

      t.timestamps
    end
  end
end
