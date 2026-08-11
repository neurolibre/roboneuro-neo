# frozen_string_literal: true

require 'spec_helper'

# These specs cover only the access control in front of the COAR Notify
# routes. Every expectation here is satisfied before a request reaches a
# handler, so none of them need a database.
RSpec.describe 'COAR Notify access control' do
  describe 'dashboard' do
    context 'when no credentials are configured' do
      before do
        allow(CoarNotify).to receive(:dashboard_configured?).and_return(false)
      end

      it 'refuses to serve the dashboard' do
        get '/coar_notify/dashboard'
        expect(last_response.status).to eq(503)
      end

      it 'refuses to serve a notification detail page' do
        get '/coar_notify/dashboard/1'
        expect(last_response.status).to eq(503)
      end

      it 'refuses to serve a payload' do
        get '/coar_notify/dashboard/api/1/payload'
        expect(last_response.status).to eq(503)
      end
    end

    context 'when credentials are configured' do
      before do
        allow(CoarNotify).to receive(:dashboard_configured?).and_return(true)
        allow(CoarNotify).to receive(:dashboard_user).and_return('editor')
        allow(CoarNotify).to receive(:dashboard_password).and_return('s3cret')
      end

      it 'challenges a request with no credentials' do
        get '/coar_notify/dashboard'
        expect(last_response.status).to eq(401)
        expect(last_response.headers['WWW-Authenticate']).to include('Basic')
      end

      it 'rejects a wrong password' do
        basic_authorize 'editor', 'wrong'
        get '/coar_notify/dashboard'
        expect(last_response.status).to eq(401)
      end

      it 'rejects a wrong username' do
        basic_authorize 'nobody', 's3cret'
        get '/coar_notify/dashboard'
        expect(last_response.status).to eq(401)
      end

      it 'does not leak payloads to an unauthenticated request' do
        get '/coar_notify/dashboard/api/1/payload'
        expect(last_response.status).to eq(401)
        expect(last_response.body).not_to include('payload')
      end
    end
  end

  describe 'outbox' do
    let(:endpoints) do
      [
        '/coar_notify/outbox',
        '/coar_notify/outbox/endorsement',
        '/coar_notify/outbox/announce-review'
      ]
    end

    context 'when no secret is configured' do
      before { allow(CoarNotify).to receive(:outbox_secret).and_return(nil) }

      it 'refuses every outbox endpoint' do
        endpoints.each do |endpoint|
          post endpoint, '{}', 'CONTENT_TYPE' => 'application/json'
          expect(last_response.status).to eq(503), "expected 503 from #{endpoint}"
        end
      end
    end

    context 'when a secret is configured' do
      before { allow(CoarNotify).to receive(:outbox_secret).and_return('right-secret') }

      it 'rejects a request with no secret' do
        endpoints.each do |endpoint|
          post endpoint, '{}', 'CONTENT_TYPE' => 'application/json'
          expect(last_response.status).to eq(401), "expected 401 from #{endpoint}"
        end
      end

      it 'rejects a wrong bearer token' do
        post '/coar_notify/outbox', '{}',
             'CONTENT_TYPE' => 'application/json',
             'HTTP_AUTHORIZATION' => 'Bearer wrong-secret'
        expect(last_response.status).to eq(401)
      end

      it 'rejects a wrong secret parameter' do
        post '/coar_notify/outbox', { secret: 'wrong-secret' }
        expect(last_response.status).to eq(401)
      end

      it 'accepts the right bearer token and passes it to the handler' do
        post '/coar_notify/outbox', '{}',
             'CONTENT_TYPE' => 'application/json',
             'HTTP_AUTHORIZATION' => 'Bearer right-secret'
        # The body is not a valid notification, so the handler rejects it.
        # The point is that it got past authentication at all.
        expect(last_response.status).not_to eq(401)
        expect(last_response.status).not_to eq(503)
      end
    end
  end
end

# Access control on the dashboard's state changing actions. These stop before
# touching the database, so they need no test database.
RSpec.describe 'COAR Notify dashboard actions' do
  before do
    allow(CoarNotify).to receive(:dashboard_configured?).and_return(true)
    allow(CoarNotify).to receive(:dashboard_user).and_return('editor')
    allow(CoarNotify).to receive(:dashboard_password).and_return('s3cret')
  end

  %w[retry cancel].each do |action|
    describe "POST /coar_notify/dashboard/:id/#{action}" do
      it 'challenges an unauthenticated request' do
        post "/coar_notify/dashboard/1/#{action}"
        expect(last_response.status).to eq(401)
      end

      it 'rejects an authenticated request with no action token' do
        basic_authorize 'editor', 's3cret'
        post "/coar_notify/dashboard/1/#{action}"
        expect(last_response.status).to eq(403)
      end

      it 'rejects an authenticated request with a wrong action token' do
        basic_authorize 'editor', 's3cret'
        post "/coar_notify/dashboard/1/#{action}", token: 'not-the-token'
        expect(last_response.status).to eq(403)
      end

      it 'rejects a token minted for the other action' do
        other = action == 'retry' ? 'cancel' : 'retry'
        token = OpenSSL::HMAC.hexdigest('SHA256', 's3cret', "#{other}:1")

        basic_authorize 'editor', 's3cret'
        post "/coar_notify/dashboard/1/#{action}", token: token
        expect(last_response.status).to eq(403)
      end

      it 'rejects a token minted for a different record' do
        token = OpenSSL::HMAC.hexdigest('SHA256', 's3cret', "#{action}:999")

        basic_authorize 'editor', 's3cret'
        post "/coar_notify/dashboard/1/#{action}", token: token
        expect(last_response.status).to eq(403)
      end
    end
  end
end
