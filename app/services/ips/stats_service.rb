# frozen_string_literal: true

require 'time'

require_relative '../base_service'
require_relative '../errors'

module Services
  module Ips
    class StatsService < BaseService
      STATS_KEYS = %i[
        avg_rtt_ms min_rtt_ms max_rtt_ms median_rtt_ms stddev_rtt_ms loss_percent
      ].freeze

      option :repo

      def call(id:, time_from:, time_to:)
        ip = repo.find_ip(id: id)
        raise Errors::NotFoundError, 'ip not found' if ip.nil?

        from_time = coerce_time(time_from).utc
        to_time = coerce_time(time_to).utc

        row = repo.ip_stats(
          ip_id: id,
          time_from: from_time,
          time_to: to_time
        )

        if row.nil? || row[:total_checks].to_i.zero?
          raise Errors::UnprocessableError, 'no checks available for requested period'
        end

        STATS_KEYS.to_h { |key| [key, float_or_nil(row[key])] }
      end

      private

      def coerce_time(value)
        return value if value.is_a?(Time)

        Time.iso8601(value)
      end

      def float_or_nil(value)
        return nil if value.nil?

        value.to_f
      end
    end
  end
end
