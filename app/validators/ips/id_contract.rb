# frozen_string_literal: true

require 'dry-validation'

require_relative '../application_contract'
require_relative 'schemas'

module Validators
  module Ips
    class IdContract < ApplicationContract
      params(Schemas::ID_PARAM)

      rule(:id).validate(:positive_id)
    end
  end
end
