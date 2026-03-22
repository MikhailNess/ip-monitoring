# frozen_string_literal: true

module Api
  module ErrorResponses
    module_function

    def not_found(message)
      { error: { code: 'NOT_FOUND', message: message } }
    end

    def bad_request(details)
      details_hash = details.is_a?(Hash) ? details : { message: details }
      { error: { code: 'BAD_REQUEST', details: details_hash } }
    end

    def conflict(message)
      { error: { code: 'CONFLICT', message: message } }
    end

    def unprocessable(message)
      { error: { code: 'UNPROCESSABLE_ENTITY', message: message } }
    end
  end
end
