# frozen_string_literal: true

module Consumer
  class Caller
    def call
      Needed::Thing.new
    end
  end
end
