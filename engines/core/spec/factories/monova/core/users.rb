# frozen_string_literal: true

FactoryBot.define do
  factory :core_user, class: "Monova::Core::User" do
    sequence(:email) { |number| "user#{number}@example.com" }
    password { "correct horse battery staple" }
  end
end
