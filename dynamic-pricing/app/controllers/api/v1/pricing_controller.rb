class Api::V1::PricingController < ApplicationController
  VALID_PERIODS = RateApiClient::VALID_PERIODS
  VALID_HOTELS  = RateApiClient::VALID_HOTELS
  VALID_ROOMS   = RateApiClient::VALID_ROOMS

  before_action :validate_params

  def index
    period = params[:period]
    hotel  = params[:hotel]
    room   = params[:room]

    service = Api::V1::PricingService.new(period:, hotel:, room:)
    service.run
    if service.valid?
      render json: { rate: service.result }
    else
      status = service.upstream_error? ? :bad_gateway : :bad_request
      render json: { error: service.errors.join(', '), code: service.error_code }, status: status
    end
  end

  private

  def validate_params
    # Validate required parameters
    unless params[:period].present? && params[:hotel].present? && params[:room].present?
      return render json: { error: "Missing required parameters: period, hotel, room", code: :invalid_params }, status: :bad_request
    end

    # Validate parameter values
    unless VALID_PERIODS.include?(params[:period])
      return render json: { error: "Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}", code: :invalid_params }, status: :bad_request
    end

    unless VALID_HOTELS.include?(params[:hotel])
      return render json: { error: "Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}", code: :invalid_params }, status: :bad_request
    end

    unless VALID_ROOMS.include?(params[:room])
      return render json: { error: "Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}", code: :invalid_params }, status: :bad_request
    end
  end
end
