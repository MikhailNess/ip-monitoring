# frozen_string_literal: true

ENV['RACK_ENV'] = 'test'

require_relative '../config/environment'
require 'json'
require 'rspec'
require 'rack/test'
require 'sequel/extensions/migration'

migrations_path = File.expand_path('../migrations', __dir__)
Sequel::Migrator.run(DB, migrations_path)

RSpec.configure do |config|
  config.pattern = 'spec/**/*_spec.rb'
  config.exclude_pattern = 'vendor/**/*'

  config.include Rack::Test::Methods

  config.before(:each, type: :request) do
    DB.run('TRUNCATE ip_checks, ip_activity_periods, ips RESTART IDENTITY CASCADE')
  end
end

def app
  Api::App
end
