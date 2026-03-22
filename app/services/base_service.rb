# frozen_string_literal: true

require 'dry/initializer'

module Services
  class BaseService
    extend Dry::Initializer

    option :now_provider, default: -> { Time.now.utc }

    protected

    def utc_now
      t = now_provider
      t.is_a?(Proc) ? t.call.utc : t.utc
    end
  end
end
