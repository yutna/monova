# frozen_string_literal: true

# AUTH-07, DATA-07: core_tenants is one of the two global tables. It
# holds a tenant's identity, never tenant data; the check constraint
# mirrors the model's presence validation.
class CreateCoreTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :core_tenants do |t|
      t.text :name, null: false
      t.timestamps
      t.check_constraint "btrim(name) <> ''", name: "core_tenants_name_not_blank"
    end
  end
end
