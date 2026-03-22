# frozen_string_literal: true

require 'time'
require 'dry-validation'

require_relative '../application_contract'
require_relative 'schemas'

module Validators
  module Ips
    class StatsContract < ApplicationContract
      params(Schemas::ID_PARAM) do
        required(:time_from).filled(:string)
        required(:time_to).filled(:string)
      end

      rule(:id).validate(:positive_id)

      rule(:time_from) do
        Time.iso8601(value)
      rescue ArgumentError
        key.failure('must be a valid ISO8601 datetime')
      end

      rule(:time_to) do
        Time.iso8601(value)
      rescue ArgumentError
        key.failure('must be a valid ISO8601 datetime')
      end

      rule(:time_from, :time_to) do
        from = values[:time_from]
        to = values[:time_to]
        next if from.nil? || to.nil?

        from_time = Time.iso8601(from)
        to_time = Time.iso8601(to)
        key.failure('time_from must be <= time_to') if from_time > to_time
      end
    end
  end
end
