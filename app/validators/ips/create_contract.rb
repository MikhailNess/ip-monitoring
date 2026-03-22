# frozen_string_literal: true

require 'dry-validation'
require 'ipaddr'

require_relative '../application_contract'

module Validators
  module Ips
    class CreateContract < ApplicationContract
      params do
        required(:ip).filled(:string)
        required(:enabled).filled(:bool)
      end

      rule(:ip) do
        IPAddr.new(value)
      rescue IPAddr::InvalidAddressError
        key.failure('must be a valid IPv4 or IPv6 address')
      end
    end
  end
end
