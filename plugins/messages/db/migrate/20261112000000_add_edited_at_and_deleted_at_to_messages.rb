class AddEditedAtAndDeletedAtToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :edited_at, :datetime
    add_column :messages, :deleted_at, :datetime
  end
end
