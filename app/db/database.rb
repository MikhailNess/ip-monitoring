# frozen_string_literal: true

require 'sequel'
require 'logger'

ENV['RACK_ENV'] ||= 'development'

database_url = ENV.fetch('DATABASE_URL')

Sequel.default_timezone = :utc

DB = Sequel.connect(
  database_url,
  max_connections: Integer(ENV.fetch('DB_POOL', 5)),
  pool_timeout: Integer(ENV.fetch('DB_POOL_TIMEOUT', 5))
)

DB.timezone = :utc

DB.loggers << Logger.new($stdout) if %w[development test].include?(ENV['RACK_ENV'])
