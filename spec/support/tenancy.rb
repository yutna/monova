# frozen_string_literal: true

# AUTH-12, TS-03: Rails wraps a transactional example in a real database
# transaction and marks its connection as pinned. That transaction is test
# scaffolding, not application work, so it must not make the tenancy helper
# refuse a second tenant in the same example. The exemption is explicit and
# lives here, in the spec suite: production code has no switch for it and
# never reads `pinned`.
module TenancyFixtureExemption
  private

  def remember(connection, id)
    return if connection.pinned

    super
  end
end

Monova::Core::Tenancy.singleton_class.prepend(TenancyFixtureExemption)
