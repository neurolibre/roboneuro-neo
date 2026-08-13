require 'uri'
require 'json'
require 'time'
require 'yaml'
require 'faraday'
require 'logger'
require_relative 'github'


include GitHub


# Move these to ENV later.
$TEST_DOMAIN="https://preview.neurolibre.org"
$TEST_SSL = true


module NeurolibreUtilities

    def neurolibre_test_client
        @neurolibre_test_client = Faraday.new(url: $TEST_DOMAIN) do |faraday|
          faraday.request :json
          faraday.ssl.verify = $TEST_SSL
          faraday.request :authorization, :basic, ENV['PREVIEW_API_USER'], ENV['PREVIEW_API_KEY']
        end
      end

    def request_book_build_test(payload_in)

        response = neurolibre_test_client.post('/api/book/build/test', payload_in.to_json)
        Logger.new(STDOUT).warn(response)

    end

end
