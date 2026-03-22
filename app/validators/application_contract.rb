# frozen_string_literal: true

require 'dry-validation'

module Validators
  class ApplicationContract < Dry::Validation::Contract
    register_macro(:positive_id) do
      key.failure('must be positive') if value <= 0
    end
  end
end
