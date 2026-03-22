# frozen_string_literal: true

require_relative 'config/environment'

require 'logger'
require 'sequel/extensions/migration'

migrations_path = File.expand_path('migrations', __dir__)

namespace :db do
  desc 'Run Sequel migrations'
  task :migrate do
    logger = Logger.new($stdout)
    # Sequel stores migration versioning in its own schema_migrations table.
    DB.loggers << logger
    Sequel::Migrator.run(DB, migrations_path)
  end
end

begin
  require 'rspec/core/rake_task'
  RSpec::Core::RakeTask.new(:spec)
rescue LoadError
  # rspec только в development/test
end
