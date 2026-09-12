class ShrinkUsersIndexedColumnsForUtf8mb4 < ActiveRecord::Migration
  # Reduce indexed VARCHAR columns from 255 to 191 so they fit under MySQL 5.5's
  # 767-byte InnoDB index limit when the table charset is utf8mb4 (4 bytes/char,
  # so 255 * 4 = 1020 > 767; 191 * 4 = 764 <= 767).
  #
  # Already applied on prod by hand during the utf8mb4 migration (2026-05-11);
  # marked as applied via direct INSERT INTO schema_migrations. This migration
  # exists so fresh environments (db:schema:load / db:migrate) reach the same
  # state. On MySQL 5.7+ with innodb_large_prefix=ON the shrink is unnecessary
  # but harmless.

  def up
    change_column :users, :email, :string, :limit => 191
    change_column :users, :remember_token, :string, :limit => 191
  end

  def down
    change_column :users, :email, :string, :limit => 255
    change_column :users, :remember_token, :string, :limit => 255
  end
end
