# frozen_string_literal: true

require 'dry-schema'

module Validators
  module Ips
    module Schemas
      ID_PARAM = Dry::Schema.Params do
        required(:id).filled(:integer)
      end
    end
  end
end
