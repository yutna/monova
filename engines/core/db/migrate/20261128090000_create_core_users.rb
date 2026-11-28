# frozen_string_literal: true

# AUTH-07, DATA-12: core_users is one of the two global tables, so it has
# no tenant_id and no policy. The email is encrypted non-deterministically
# and a unique digest column serves the lookup; the password is stored only
# as a bcrypt digest (AUTH-02).
class CreateCoreUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :core_users do |t|
      t.text :email, null: false
      t.text :email_digest, null: false
      t.text :password_digest, null: false
      t.timestamps
      t.index :email_digest, unique: true
    end
  end
end
