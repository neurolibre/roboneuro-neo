# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'rack/utils'
require 'rack/auth/basic'
require 'openssl'

module CoarNotify
  module Routes
    # Web UI for viewing COAR Notify notifications (inbox and outbox)
    #
    # The dashboard exposes reviewer identities, review summaries and full
    # notification payloads, so it is protected by basic auth and refuses to
    # serve anything unless credentials have been configured.
    class Dashboard < Sinatra::Base
      # Configure Sinatra. The views are self contained and reference no
      # static assets, so no public folder is declared.
      set :views, File.join(__dir__, '../views')

      # Refuse to serve at all when no credentials are set, so that a
      # partially configured deploy cannot publish the notification table.
      # Checked before authentication so the reason is distinguishable.
      before '/coar_notify/dashboard*' do
        unless CoarNotify.dashboard_configured?
          halt 503, 'COAR Notify dashboard is not configured'
        end

        unless authorized?
          headers['WWW-Authenticate'] = 'Basic realm="COAR Notify dashboard"'
          halt 401, 'Unauthorized'
        end
      end

      helpers do
        # Token binding a state changing action to a specific record
        #
        # Basic auth alone is not enough for a form: browsers resend those
        # credentials automatically, so any page could trigger a retry. The
        # token is keyed on the dashboard password, which an attacker's page
        # cannot know, and it is scoped to one action on one record.
        #
        # @param action [String] action name
        # @param id [Integer, String] notification record id
        # @return [String] hex token
        def action_token(action, id)
          OpenSSL::HMAC.hexdigest(
            'SHA256',
            CoarNotify.dashboard_password.to_s,
            "#{action}:#{id}"
          )
        end

        # Reject the request unless it carries the right token
        # @param action [String] action name
        # @param id [Integer, String] notification record id
        def verify_action_token!(action, id)
          presented = params[:token].to_s
          expected = action_token(action, id)

          return if !presented.empty? && Rack::Utils.secure_compare(presented, expected)

          halt 403, 'Invalid or missing action token'
        end

        # Check basic auth credentials against the configured pair
        # @return [Boolean] true when the request is authenticated
        def authorized?
          auth = Rack::Auth::Basic::Request.new(request.env)
          return false unless auth.provided? && auth.basic? && auth.credentials

          user, password = auth.credentials

          # Constant time comparison on both halves, and & rather than &&
          # so that a wrong username costs the same as a wrong password.
          Rack::Utils.secure_compare(user.to_s, CoarNotify.dashboard_user) &
            Rack::Utils.secure_compare(password.to_s, CoarNotify.dashboard_password)
        end
      end

      # Main dashboard view
      get '/coar_notify/dashboard' do
        # Get filter parameters
        status_filter = params[:status]
        service_filter = params[:service]
        direction_filter = params[:direction] || 'received'

        # Build query
        query = CoarNotify::Models::Notification.where(direction: direction_filter)
        query = query.where(status: status_filter) if status_filter && !status_filter.empty?
        query = query.where(service_name: service_filter) if service_filter && !service_filter.empty?

        # Get notifications ordered by most recent first
        @notifications = query.order(Sequel.desc(:created_at)).limit(100).all

        # Get unique services for filter dropdown
        @services = CoarNotify::Models::Notification
          .where(direction: direction_filter)
          .select(:service_name)
          .distinct
          .map(:service_name)
          .compact
          .sort

        # Get stats
        @stats = {
          total: CoarNotify::Models::Notification.where(direction: direction_filter).count,
          pending: CoarNotify::Models::Notification.where(direction: direction_filter, status: 'pending').count,
          processing: CoarNotify::Models::Notification.where(direction: direction_filter, status: 'processing').count,
          processed: CoarNotify::Models::Notification.where(direction: direction_filter, status: 'processed').count,
          failed: CoarNotify::Models::Notification.where(direction: direction_filter, status: 'failed').count,
          cancelled: CoarNotify::Models::Notification.where(direction: direction_filter, status: 'cancelled').count
        }

        @current_status = status_filter
        @current_service = service_filter
        @current_direction = direction_filter

        erb :dashboard
      end

      # View individual notification details
      get '/coar_notify/dashboard/:id' do
        @notification = CoarNotify::Models::Notification.where(id: params[:id]).first
        halt 404, 'Notification not found' unless @notification

        erb :notification_detail
      end

      # Retry a failed notification
      #
      # Re-enqueues the worker for this record's direction. New review
      # requests are deliberately not offered here: those stay with the
      # `coar request from <service>` command, so that the decision is
      # attributed to an editor and logged in the review issue.
      post '/coar_notify/dashboard/:id/retry' do
        # Checked before the lookup, so a forged request does no database work.
        verify_action_token!('retry', params[:id])

        notification = CoarNotify::Models::Notification.where(id: params[:id]).first
        halt 404, 'Notification not found' unless notification

        unless notification.retryable?
          halt 409, "Only failed notifications can be retried (this one is #{notification.status})"
        end

        notification.update(status: 'pending', error_message: nil, updated_at: Time.now)

        if notification.direction == 'sent'
          CoarNotify::Workers::SendWorker.perform_async(
            notification.issue_id,
            notification.service_name,
            notification.send_action
          )
        else
          CoarNotify::Workers::ReceiveWorker.perform_async(notification.id)
        end

        redirect "/coar_notify/dashboard/#{notification.id}"
      end

      # Cancel a pending notification
      post '/coar_notify/dashboard/:id/cancel' do
        # Checked before the lookup, so a forged request does no database work.
        verify_action_token!('cancel', params[:id])

        notification = CoarNotify::Models::Notification.where(id: params[:id]).first
        halt 404, 'Notification not found' unless notification

        unless notification.cancellable?
          halt 409, "Only pending notifications can be cancelled (this one is #{notification.status})"
        end

        notification.mark_cancelled!

        redirect "/coar_notify/dashboard/#{notification.id}"
      end

      # API endpoint to get notification payload as JSON
      get '/coar_notify/dashboard/api/:id/payload' do
        content_type :json
        notification = CoarNotify::Models::Notification.where(id: params[:id]).first
        halt 404, { error: 'Notification not found' }.to_json unless notification

        JSON.pretty_generate(notification.payload)
      end
    end
  end
end
