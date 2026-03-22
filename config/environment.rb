# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default)

require 'dotenv/load' if (ENV['RACK_ENV'] || 'development') == 'development'

require_relative '../app/db/database'
require_relative '../app/api/app'
