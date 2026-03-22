# frozen_string_literal: true

require_relative '../base_service'
require_relative '../errors'

module Services
  module Ips
    class DisableService < BaseService
      option :repo

      def call(id:)
        now_utc = utc_now

        repo.transaction do
          ip = repo.find_ip_for_update(id: id, include_deleted: false)
          raise Errors::NotFoundError, 'ip not found' if ip.nil?

          changed = repo.close_open_activity_period(
            ip_id: id,
            ended_at: now_utc,
            now: now_utc
          ).to_i.positive?

          { id: id, enabled: false, changed: changed }
        end
      end
    end
  end
end
