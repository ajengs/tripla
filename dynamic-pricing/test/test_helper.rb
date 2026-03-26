ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"
require "stoplight"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers
  parallelize(workers: 1)

  setup do
    capture_io do
      Stoplight.configure do |c|
        c.data_store = Stoplight::DataStore::Memory.new
        c.notifiers  = []
      end
    end
  end
end
