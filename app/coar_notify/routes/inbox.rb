# frozen_string_literal: true

require 'sinatra/base'
require 'json'

module CoarNotify
  module Routes
    # Sinatra routes for COAR Notify inbox (W3C LDN compliant)
    #
    # Endpoints:
    # - POST /coar_notify/inbox - Receive notification
    # - GET /coar_notify/inbox - List received notifications
    # - GET /coar_notify/inbox/notifications/:id - Get specific notification
    #
    # All endpoints return application/ld+json content type
    class Inbox < Sinatra::Base
      # Disable sessions (stateless API)
      disable :sessions

      # Only guard this middleware's own endpoints. A bare `before` in a
      # Sinatra app mounted with `use` runs for every request passing
      # through the chain, including ones bound for the host app.
      before '/coar_notify/inbox*' do
        unless CoarNotify.enabled?
          halt 503, json_response(
            error: 'COAR Notify is not enabled',
            details: 'Set COAR_NOTIFY_ENABLED=true to enable this feature'
          )
        end
      end

      # POST /coar_notify/inbox - Receive notification (W3C LDN endpoint)
      #
      # Accepts JSON-LD notification, validates it, stores it, and
      # returns HTTP 201 Created with Location header.
      #
      # Returns:
      # - 201 Created: Notification received and stored
      # - 200 OK: Notification already received (idempotent)
      # - 400 Bad Request: Invalid notification
      # - 403 Forbidden: IP not whitelisted
      # - 500 Internal Server Error: Processing failed
      post '/coar_notify/inbox' do
        content_type 'application/ld+json'

        begin
          # Read request body
          request.body.rewind
          json_body = request.body.read

          # Receive and persist notification
          receiver = Services::Receiver.new
          result = receiver.receive(json_body, request_ip: request.ip)

          case result[:status]
          when :created
            status 201
            headers 'Location' => result[:location]
            json_response(
              message: 'Notification received',
              id: result[:location],
              record_id: result[:record_id]
            )

          when :ok
            status 200
            json_response(
              message: result[:message],
              id: result[:location]
            )
          end

        rescue SecurityError => e
          status 403
          json_response(
            error: 'Forbidden',
            details: e.message
          )

        rescue Coarnotify::Server::COARNotifyServerError => e
          status e.status_code
          json_response(
            error: 'COAR Notify server error',
            details: e.message,
            status_code: e.status_code
          )

        rescue Coarnotify::ValidationError => e
          status 400
          json_response(
            error: 'Invalid notification',
            details: format_validation_errors(e.errors)
          )

        rescue JSON::ParserError => e
          status 400
          json_response(
            error: 'Invalid JSON',
            details: e.message
          )

        rescue => e
          # Log unexpected errors to both logger and stderr
          error_msg = "COAR Notify inbox error: #{e.class} - #{e.message}"
          backtrace = e.backtrace ? e.backtrace.join("\n") : "No backtrace available"

          logger.error(error_msg)
          logger.error(backtrace)

          # Also print to stderr for immediate visibility
          $stderr.puts "\n" + "=" * 80
          $stderr.puts error_msg
          $stderr.puts backtrace
          $stderr.puts "=" * 80 + "\n"

          # Notify error tracking service if available
          Honeybadger.notify(e) if defined?(Honeybadger)

          status 500
          json_response(error: 'Internal server error')
        end
      end

      # GET /coar_notify/inbox - List received notifications (W3C LDN endpoint)
      #
      # Returns a JSON-LD container with links to all received notifications.
      # Supports pagination via limit and offset query parameters.
      #
      # Query parameters:
      # - limit: Maximum number of notifications (default: 100, max: 1000)
      # - offset: Pagination offset (default: 0)
      #
      # Returns:
      # - 200 OK: List of notification URLs
      get '/coar_notify/inbox' do
        content_type 'application/ld+json'

        limit = [(params[:limit] || 100).to_i, 1000].min
        offset = (params[:offset] || 0).to_i

        receiver = Services::Receiver.new
        notifications = receiver.list_notifications(limit: limit, offset: offset)

        # W3C LDN-compliant response format
        ldp_container = {
          '@context' => 'http://www.w3.org/ns/ldp',
          '@id' => "#{request.base_url}/coar_notify/inbox/",
          '@type' => 'ldp:Container',
          'ldp:contains' => notifications.map { |n| n.notification_id }
        }

        json_response(ldp_container)
      end

      # GET /coar_notify/inbox/notifications/:id - Get specific notification
      #
      # Returns the full JSON-LD payload of a specific notification.
      #
      # Returns:
      # - 200 OK: Notification payload
      # - 404 Not Found: Notification not found
      get '/coar_notify/inbox/notifications/:id' do
        content_type 'application/ld+json'

        # Use the notification ID from the URL parameter directly
        # The ID is already the full URN/URI (e.g., urn:uuid:...)
        notification_id = params[:id]

        receiver = Services::Receiver.new
        notification = receiver.get_notification(notification_id)

        if notification
          # Return original JSON-LD payload
          json_response(notification.payload)
        else
          status 404
          json_response(
            error: 'Notification not found',
            id: "#{request.base_url}/coar_notify/inbox/notifications/#{notification_id}"
          )
        end
      end

      # Helper methods
      helpers do
        # Format JSON response
        #
        # @param data [Hash, Array] data to serialize
        # @return [String] JSON string
        def json_response(data)
          JSON.pretty_generate(data)
        end

        # Format validation errors for response
        #
        # @param errors [Hash] validation errors from coarnotifyrb
        # @return [Hash] formatted errors
        def format_validation_errors(errors)
          return errors if errors.is_a?(String)

          # coarnotifyrb returns nested error structure
          errors.transform_values do |error_info|
            if error_info.is_a?(Hash)
              {
                errors: error_info['errors'] || [],
                nested: error_info['nested'] || {}
              }
            else
              error_info
            end
          end
        end
      end
    end
  end
end
