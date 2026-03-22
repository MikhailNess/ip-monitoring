# frozen_string_literal: true

require_relative '../base_service'
require_relative '../errors'

module Services
  module Ips
    class EnableService < BaseService
      option :repo

      def call(id:)
        now_utc = utc_now

        repo.transaction do
          ip = repo.find_ip_for_update(id: id, include_deleted: false)
          raise Errors::NotFoundError, 'ip not found' if ip.nil?

          if repo.find_open_activity_period(ip_id: id)
            { id: id, enabled: true, changed: false }
          else
            repo.insert_open_activity_period(
              ip_id: id,
              started_at: now_utc,
              now: now_utc
            )
            { id: id, enabled: true, changed: true }
          end
        end
      end
    end
  end
end
