# frozen_string_literal: true

require 'ipaddr'

require_relative '../base_service'

module Services
  module IpChecks
    # Один ICMP ping, запись результата в репозиторий. Таймаут задаётся timeout_seconds;
    # процесс при необходимости убивается по монотонным часам (см. #wait_for_ping_exit).
    class PingCheckService < BaseService
      DEFAULT_TIMEOUT_SECONDS = 1.0
      RTT_MS_PATTERN = /time=([0-9.]+)\s*ms/i
      POLL_INTERVAL = 0.01 # секунды между проверками waitpid

      def self.parse_rtt_ms(ping_output)
        ping_output[RTT_MS_PATTERN, 1]&.to_f
      end

      option :repo
      option :timeout_seconds, default: -> { DEFAULT_TIMEOUT_SECONDS }

      def call(ip_id:, ip:, checked_at:)
        check_status, round_trip_ms = execute_ping(ip_string: ip)
        if check_status == 'success' && round_trip_ms && round_trip_ms > max_reasonable_rtt_ms
          check_status = 'timeout'
          round_trip_ms = nil
        end

        repo.insert_ip_check!(
          ip_id: ip_id,
          status: check_status,
          rtt_ms: round_trip_ms,
          checked_at: checked_at
        )
      end

      private

      # Возвращает [status для БД, rtt_ms или nil].
      def execute_ping(ip_string:)
        ip_address = IPAddr.new(ip_string)
        stdout_reader, stdout_writer = IO.pipe
        stderr_reader, stderr_writer = IO.pipe

        ping_pid = Process.spawn(
          *ping_command_argv(ip_address: ip_address, target: ip_string),
          out: stdout_writer,
          err: stderr_writer
        )
        [stdout_writer, stderr_writer].each(&:close)

        deadline_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds.to_f
        killed_after_deadline, process_status = wait_for_ping_exit(
          pid: ping_pid,
          deadline_monotonic: deadline_monotonic,
          stdout_writer: stdout_writer,
          stderr_writer: stderr_writer
        )

        merged_output = read_streams_then_close(stdout_reader, stderr_reader)
        interpret_ping_output(merged_output, killed_after_deadline, process_status)
      rescue IPAddr::InvalidAddressError, SystemCallError, IOError
        ['error', nil]
      end

      def ping_command_argv(ip_address:, target:)
        family_flag = ip_address.ipv6? ? %w[-6] : %w[-4]
        # Минимум 1 с: флаг -W у ping; жёсткий предел — kill в wait_for_ping_exit.
        ping_builtin_wait_sec = [timeout_seconds.to_i, 1].max

        ['ping', *family_flag, '-c', '1', '-n', '-W', ping_builtin_wait_sec.to_s, target]
      end

      # Дожидается завершения дочернего ping или шлёт KILL по истечении deadline_monotonic.
      # Возвращает [был_ли_kill_по_таймауту, Process::Status].
      def wait_for_ping_exit(pid:, deadline_monotonic:, stdout_writer:, stderr_writer:)
        killed_after_deadline = false
        process_status = nil

        begin
          loop do
            if Process.waitpid(pid, Process::WNOHANG)
              process_status = $?
              break
            end

            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_monotonic
              killed_after_deadline = true
              Process.kill('KILL', pid)
              Process.waitpid(pid)
              process_status = $?
              break
            end

            sleep POLL_INTERVAL
          end
        ensure
          [stdout_writer, stderr_writer].each { |io| io.close unless io.closed? }
        end

        [killed_after_deadline, process_status]
      end

      def read_streams_then_close(stdout_reader, stderr_reader)
        [stdout_reader, stderr_reader].map(&:read).tap { [stdout_reader, stderr_reader].each(&:close) }.join(' ')
      end

      def interpret_ping_output(merged_output, killed_after_deadline, process_status)
        return ['timeout', nil] if killed_after_deadline || merged_output.match?(/timed out|timeout/i)

        if process_status&.success?
          round_trip_ms = self.class.parse_rtt_ms(merged_output)
          return ['success', round_trip_ms] if round_trip_ms && round_trip_ms >= 0
        end

        merged_output.match?(/100% packet loss/i) ? ['timeout', nil] : ['error', nil]
      end

      def max_reasonable_rtt_ms
        timeout_seconds.to_f * 1000.0
      end
    end
  end
end
