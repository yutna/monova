# frozen_string_literal: true

module Monova
  module Core
    # ARCH-03: the abstract base record every engine model inherits. A
    # model that names no table still carries the connection settings
    # core gives every table (DATA-08, DATA-10).
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true
    end
  end
end
