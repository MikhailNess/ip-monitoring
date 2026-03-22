# frozen_string_literal: true

require 'sequel'

require_relative '../services/errors'

module Repositories
  class IpRepository
    IP_STATS_SQL = File.read(File.expand_path('sql/ip_stats.sql', __dir__)).freeze

    def initialize(db:)
      @db = db
    end

    def transaction(&)
      @db.transaction(&)
    end

    def create_ip_row(ip:, now:)
      @db[:ips].insert(
        ip: ip,
        created_at: now,
        updated_at: now,
        deleted_at: nil
      )
    rescue ::Sequel::UniqueConstraintViolation
      raise Errors::ConflictError, 'ip already exists'
    end

    def find_active_ip_by_ip(ip:)
      @db[:ips].where(ip: ip, deleted_at: nil).first
    end

    def find_latest_deleted_ip_by_ip_for_update(ip:)
      @db[:ips]
        .where(ip: ip)
        .exclude(deleted_at: nil)
        .order(Sequel.desc(:id))
        .limit(1)
        .for_update
        .first
    end

    def restore_ip_row(ip_id:, now:)
      @db[:ips].where(id: ip_id).exclude(deleted_at: nil).update(
        deleted_at: nil,
        updated_at: now
      )
    end

    def find_ip(id:, include_deleted: false)
      ds = @db[:ips].where(id: id)
      ds = ds.where(deleted_at: nil) unless include_deleted
      ds.first
    end

    # Блокирует строку ips до конца транзакции (FOR UPDATE).
    # Сериализует enable/disable/delete и открытие периода для одного IP.
    def find_ip_for_update(id:, include_deleted: false)
      ds = @db[:ips].where(id: id)
      ds = ds.where(deleted_at: nil) unless include_deleted
      ds.for_update.first
    end

    def find_open_activity_period(ip_id:)
      @db[:ip_activity_periods].where(ip_id: ip_id, ended_at: nil).first
    end

    def insert_open_activity_period(ip_id:, started_at:, now:)
      @db[:ip_activity_periods].insert(
        ip_id: ip_id,
        started_at: started_at,
        ended_at: nil,
        created_at: now,
        updated_at: now
      )
    end

    def close_open_activity_period(ip_id:, ended_at:, now:)
      @db[:ip_activity_periods].where(ip_id: ip_id, ended_at: nil).update(
        ended_at: ended_at,
        updated_at: now
      )
    end

    def mark_ip_deleted(ip_id:, deleted_at:, now:)
      @db[:ips].where(id: ip_id, deleted_at: nil).update(
        deleted_at: deleted_at,
        updated_at: now
      )
    end

    def list_active_ips(now:)
      @db[:ip_activity_periods]
        .join(:ips, id: :ip_id)
        .where(Sequel[:ips][:deleted_at] => nil)
        .where(ended_at: nil)
        .where(Sequel[:ip_activity_periods][:started_at] <= now)
        .select(
          Sequel[:ips][:id].as(:id),
          Sequel[:ips][:ip].as(:ip)
        )
        .all
    end

    def insert_ip_check!(ip_id:, status:, rtt_ms:, checked_at:)
      @db[:ip_checks].insert(
        ip_id: ip_id,
        status: status,
        rtt_ms: rtt_ms,
        checked_at: checked_at,
        created_at: checked_at
      )
    end

    def ip_stats(ip_id:, time_from:, time_to:)
      @db[IP_STATS_SQL, ip_id: ip_id, time_from: time_from, time_to: time_to].first
    end
  end
end
