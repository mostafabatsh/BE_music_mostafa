# Load the Sinatra app
require File.dirname(__FILE__) + '/../recommendation'

require 'rspec'
require 'rack/test'
require 'json'
require 'awesome_print'

set :environment, :test

RSpec.configure do |conf|
  conf.include Rack::Test::Methods
end

def app
  Sinatra::Application
end