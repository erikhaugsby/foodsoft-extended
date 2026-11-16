# This migration comes from foodsoft_messages_engine (originally 20261112000000)
class AddEditedAtAndDeletedAtToMessages < ActiveRecord::Migration[7.0]
  def change
    add_column :messages, :edited_at, :datetime
    add_column :messages, :deleted_at, :datetime
  end
end
