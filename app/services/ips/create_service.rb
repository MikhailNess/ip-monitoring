# frozen_string_literal: true

require_relative '../base_service'
require_relative '../errors'

module Services
  module Ips
    class CreateService < BaseService
      option :repo

      def call(ip:, enabled:)
        now_utc = utc_now

        repo.transaction do
          raise Errors::ConflictError, 'ip already exists' if repo.find_active_ip_by_ip(ip: ip)

          deleted = repo.find_latest_deleted_ip_by_ip_for_update(ip: ip)
          ip_id = if deleted
                    repo.restore_ip_row(ip_id: deleted[:id], now: now_utc)
                    deleted[:id]
                  else
                    repo.create_ip_row(ip: ip, now: now_utc)
                  end

          if enabled
            locked = repo.find_ip_for_update(id: ip_id, include_deleted: true)
            raise Errors::NotFoundError, 'ip not found' if locked.nil?

            unless repo.find_open_activity_period(ip_id: ip_id)
              repo.insert_open_activity_period(
                ip_id: ip_id,
                started_at: now_utc,
                now: now_utc
              )
            end
          end

          { id: ip_id, ip: ip, enabled: enabled }
        end
      end
    end
  end
end
