# frozen_string_literal: true

require 'json'
require 'sinatra/base'

require_relative 'error_responses'
require_relative '../repositories/ip_repository'
require_relative '../services/errors'
require_relative '../services/ips/create_service'
require_relative '../services/ips/delete_service'
require_relative '../services/ips/disable_service'
require_relative '../services/ips/enable_service'
require_relative '../services/ips/stats_service'
require_relative '../validators/ips/create_contract'
require_relative '../validators/ips/id_contract'
require_relative '../validators/ips/stats_contract'

module Api
  class App < Sinatra::Base
    ID_TOGGLE_SERVICES = {
      'enable' => Services::Ips::EnableService,
      'disable' => Services::Ips::DisableService
    }.freeze

    ERROR_HANDLERS = [
      [Errors::NotFoundError, 404, :not_found],
      [Errors::BadRequest, 400, :bad_request],
      [Errors::ConflictError, 409, :conflict],
      [Errors::UnprocessableError, 422, :unprocessable]
    ].freeze

    configure do
      set :environment, ENV.fetch('RACK_ENV', 'development')
      set :json_content_type, 'application/json; charset=utf-8'
      set :ip_repository, Repositories::IpRepository.new(db: DB)
      set :public_folder, File.expand_path('../../public', __dir__)
    end

    get('/') { redirect '/demo.html' }

    before do
      p = request.path_info
      next unless p == '/ips' || p.start_with?('/ips/')

      content_type settings.json_content_type
    end

    helpers do
      def validated(contract_class)
        result = contract_class.new.call(params)
        return result.to_h if result.success?

        raise Errors::BadRequest, result.errors.to_h
      end

      def repo
        settings.ip_repository
      end

      def render_json(status_code, payload)
        status status_code
        content_type settings.json_content_type
        payload.to_json
      end
    end

    ERROR_HANDLERS.each do |error_class, status, response_method|
      error error_class do
        msg = env['sinatra.error'].message
        render_json(status, ErrorResponses.public_send(response_method, msg))
      end
    end

    post '/ips' do
      payload = validated(Validators::Ips::CreateContract)
      result = Services::Ips::CreateService.new(repo: repo).call(**payload)
      render_json(201, result)
    end

    ID_TOGGLE_SERVICES.each do |action, service_class|
      post "/ips/:id/#{action}" do
        render_json(200, service_class.new(repo: repo).call(**validated(Validators::Ips::IdContract)))
      end
    end

    get '/ips/:id/stats' do
      render_json(
        200,
        Services::Ips::StatsService.new(repo: repo).call(**validated(Validators::Ips::StatsContract))
      )
    end

    delete '/ips/:id' do
      Services::Ips::DeleteService.new(repo: repo).call(**validated(Validators::Ips::IdContract))
      status 204
    end
  end
end
