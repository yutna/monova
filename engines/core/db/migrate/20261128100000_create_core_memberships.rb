# frozen_string_literal: true

# AUTH-05, AUTH-07, AUTH-09, DATA-03, DATA-07: core_memberships is a
# tenant-owned table. core's helper fills tenant_id from the transaction's
# tenant and adds the forced AUTH-09 policy; the unique index and the check
# constraints hold the invariants the model mirrors in its validations.
class CreateCoreMemberships < ActiveRecord::Migration[8.1]
  def change
    create_table :core_memberships do |t|
      t.tenant_id
      t.uuid :user_id, null: false
      t.text :role, null: false
      t.text :status, null: false
      t.timestamps
      t.index [ :tenant_id, :user_id ], unique: true
      t.check_constraint role_expression, name: "core_memberships_role_allowed"
      t.check_constraint status_expression, name: "core_memberships_status_allowed"
      t.foreign_key :core_users, column: :user_id
    end

    add_tenant_policy :core_memberships
  end

  private

  # AUTH-05: the role names live in one place, the model's constant, so the
  # constraint and the model's validation list the same values.
  def role_expression
    "role IN (#{quoted_values(Monova::Core::Membership::ROLES)})"
  end

  def status_expression
    "status IN (#{quoted_values(Monova::Core::Membership::STATUSES)})"
  end

  def quoted_values(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end
end
