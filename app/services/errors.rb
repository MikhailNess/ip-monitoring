# frozen_string_literal: true

module Errors
  class AppError < StandardError; end

  class BadRequest < AppError; end
  class NotFoundError < AppError; end
  class ConflictError < AppError; end
  class UnprocessableError < AppError; end
end
