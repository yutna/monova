# frozen_string_literal: true

require "openssl"

module Monova
  module Core
    # AUTH-07, DATA-12: a user is found by email without a tenant. The
    # email is encrypted non-deterministically, so the lookup and its
    # unique index use an HMAC-SHA256 digest of the same normalised
    # address. Only the digest is compared; the email itself is never
    # queried.
    class User < ApplicationRecord
      EMAIL_NORMALIZATION = ->(email) { email.strip.downcase }

      has_secure_password

      encrypts :email
      normalizes :email, with: EMAIL_NORMALIZATION

      before_validation :set_email_digest

      validates :email, presence: true
      validates :email_digest, presence: true, uniqueness: true
      validates :password_digest, presence: true

      has_many :memberships

      # AUTH-07: finds a user by email in any case, with no tenant set.
      def self.find_by_email(email)
        find_by(email_digest: email_digest(email))
      end

      # DATA-12: the one place the lookup digest is computed, from the
      # email as `normalizes` stores it.
      def self.email_digest(email)
        return if email.blank?

        OpenSSL::HMAC.hexdigest("SHA256", email_digest_key, EMAIL_NORMALIZATION.call(email))
      end

      # DATA-12: development and test set a fixed, non-secret key in
      # their environment file; production reads it from credentials.
      def self.email_digest_key
        Rails.application.config.x.core.email_digest_key.presence ||
          Rails.application.credentials.dig(:core, :email_digest_key)
      end
      private_class_method :email_digest_key

      private

      def set_email_digest
        self.email_digest = self.class.email_digest(email)
      end
    end
  end
end
