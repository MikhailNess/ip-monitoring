# frozen_string_literal: true

require_relative '../config/environment'

require 'logger'

require_relative '../app/repositories/ip_repository'
require_relative '../app/services/ip_checks/ping_check_service'

interval_seconds = Integer(ENV.fetch('CHECK_INTERVAL_SECONDS', '5'))
timeout_seconds = Float(ENV.fetch('PING_TIMEOUT_SECONDS', '1'))

repo = Repositories::IpRepository.new(db: DB)
ping_check_service = Services::IpChecks::PingCheckService.new(
  repo: repo,
  timeout_seconds: timeout_seconds
)

logger = Logger.new($stdout)
logger.level = Logger.const_get(ENV.fetch('LOG_LEVEL', 'INFO'))

next_run = Process.clock_gettime(Process::CLOCK_MONOTONIC)

loop do
  now_utc = Time.now.utc
  active_ips = repo.list_active_ips(now: now_utc)

  active_ips.each do |row|
    ping_check_service.call(
      ip_id: row[:id],
      ip: row[:ip].to_s,
      checked_at: Time.now.utc
    )
  rescue StandardError => e
    logger.error("ip_check_failed ip_id=#{row[:id]} err=#{e.class}:#{e.message}")
  end

  next_run += interval_seconds
  sleep_for = next_run - Process.clock_gettime(Process::CLOCK_MONOTONIC)
  sleep(sleep_for) if sleep_for.positive?
end
