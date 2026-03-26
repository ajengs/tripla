class ApplicationController < ActionController::API
  before_action { Current.request_id = request.uuid }
end
