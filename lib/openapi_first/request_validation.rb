# frozen_string_literal: true

require 'rack'
require 'multi_json'
require_relative 'use_router'
require_relative 'error_format'
require_relative 'error_response'
require_relative './validators/request_body_validator'
require_relative './validators/parameters_validator'
require 'openapi_parameters'

module OpenapiFirst
  class RequestValidation
    prepend UseRouter

    def initialize(app, options = {})
      @app = app
      @raise = options.fetch(:raise_error, false)
    end

    def call(env)
      operation = env[OPERATION]
      return @app.call(env) unless operation

      error = catch(:error) do
        env[PARAMS] = {}
        validate_and_merge_query_params!(operation, env)
        validate_and_merge_path_params!(operation, env)
        Validators::RequestBodyValidator.call(operation, env, env[REQUEST_BODY]) if operation.request_body
        nil
      end
      if error
        raise RequestInvalidError, error[:errors] if @raise

        return ErrorResponse.render(error)
      end
      @app.call(env)
    end

    private

    def validate_and_merge_path_params!(operation, env)
      path_parameters = operation.path_parameters
      return if path_parameters.empty?

      hashy = Utils::StringKeyedHash.new(env[Router::RAW_PATH_PARAMS])
      unpacked_path_params = OpenapiParameters::Path.new(path_parameters).unpack(hashy)
      Validators::ParametersValidator.call(operation.schemas.path_parameters_schema, unpacked_path_params)
      env[PARAMS].merge!(unpacked_path_params)
    end

    def validate_and_merge_query_params!(operation, env)
      query_parameters = operation.query_parameters
      return if operation.query_parameters.empty?

      unpacked_query_params = OpenapiParameters::Query.new(query_parameters).unpack(env['QUERY_STRING'])
      Validators::ParametersValidator.call(operation.schemas.query_parameters_schema, unpacked_query_params)
      env[PARAMS].merge!(unpacked_query_params)
    end
  end
end
