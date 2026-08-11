# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'rack/utils'

module CoarNotify
  module Routes
    # COAR Notify Outbox - Send notifications to remote services
    class Outbox < Sinatra::Base
      # Every outbox route sends a notification carrying this instance's
      # service identity, so all of them require the shared secret.
      #
      # The secret may be supplied as an Authorization bearer token or as a
      # `secret` parameter, matching the convention used elsewhere for
      # roboneuro API calls. If no secret is configured the outbox is closed.
      before '/coar_notify/outbox*' do
        expected = CoarNotify.outbox_secret

        if expected.nil?
          content_type :json
          halt 503, { status: 'error',
                      message: 'Outbox is not configured' }.to_json
        end

        unless valid_secret?(expected)
          content_type :json
          halt 401, { status: 'error',
                      message: 'Unauthorized' }.to_json
        end
      end

      helpers do
        # Compare the presented secret against the configured one
        #
        # Uses a constant time comparison so that a wrong secret does not
        # leak its correct prefix through response timing.
        #
        # @param expected [String] configured secret
        # @return [Boolean] true when the request presents the right secret
        def valid_secret?(expected)
          presented = bearer_token || params[:secret]
          return false if presented.nil? || presented.empty?

          Rack::Utils.secure_compare(presented, expected)
        end

        # Extract a bearer token from the Authorization header
        # @return [String, nil] token, or nil when absent
        def bearer_token
          header = request.env['HTTP_AUTHORIZATION']
          return nil unless header

          match = header.match(/\ABearer\s+(.+)\z/i)
          match && match[1]
        end
      end

      # Send a COAR Notify notification
      # POST /coar_notify/outbox
      # Body: JSON-LD COAR Notify notification
      post '/coar_notify/outbox' do
        content_type :json

        # Parse JSON body
        request.body.rewind
        json_body = request.body.read

        begin
          # Validate and parse the notification
          notification = Coarnotify.from_json(json_body)

          # Send via the Sender service
          sender = CoarNotify::Services::Sender.new
          result = sender.send_notification(notification, json_payload: json_body)

          if result[:success]
            # Return success response
            status 202  # Accepted (async processing)
            {
              status: 'accepted',
              message: 'Notification queued for sending',
              notification_id: notification.id,
              record_id: result[:record]&.id
            }.to_json
          else
            status 500
            {
              status: 'error',
              message: result[:error] || 'Failed to send notification'
            }.to_json
          end

        rescue Coarnotify::ValidationError => e
          status 400
          {
            status: 'error',
            message: 'Invalid notification',
            details: e.message
          }.to_json
        rescue JSON::ParserError => e
          status 400
          {
            status: 'error',
            message: 'Invalid JSON',
            details: e.message
          }.to_json
        rescue => e
          logger.error("Outbox error: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n")) if e.backtrace

          status 500
          {
            status: 'error',
            message: 'Internal server error',
            details: e.message
          }.to_json
        end
      end

      # Helper endpoint to send common notification types
      # POST /coar_notify/outbox/endorsement
      # Simplified payload for endorsing a preprint
      post '/coar_notify/outbox/endorsement' do
        content_type :json

        begin
          params_hash = JSON.parse(request.body.read)

          # Build COAR Notify Endorsement (Offer + EndorsementAction)
          notification_json = {
            '@context': [
              'https://www.w3.org/ns/activitystreams',
              'https://purl.org/coar/notify'
            ],
            'id': params_hash['id'] || "urn:uuid:#{SecureRandom.uuid}",
            'type': ['Offer', 'coar-notify:EndorsementAction'],
            'origin': {
              'id': params_hash['origin_id'] || CoarNotify.service_id,
              'inbox': params_hash['origin_inbox'] || CoarNotify.inbox_url,
              'type': 'Service'
            },
            'target': {
              'id': params_hash['target_id'],
              'inbox': params_hash['target_inbox'],
              'type': 'Service'
            },
            'object': {
              'id': params_hash['object_id'],
              'ietf:cite-as': params_hash['object_doi'],
              'type': params_hash['object_type'] || ['Page', 'sorg:AboutPage']
            },
            'actor': {
              'id': params_hash['actor_id'],
              'name': params_hash['actor_name'],
              'type': params_hash['actor_type'] || 'Person'
            }
          }

          # Add optional fields
          notification_json[:object]['ietf:item'] = params_hash['object_item'] if params_hash['object_item']
          notification_json[:context] = params_hash['context'] if params_hash['context']

          # Parse and send
          notification = Coarnotify.from_hash(notification_json)
          sender = CoarNotify::Services::Sender.new
          # Pass the constructed JSON as payload
          result = sender.send_notification(notification, json_payload: notification_json.to_json)

          if result[:success]
            status 202
            {
              status: 'accepted',
              message: 'Endorsement notification queued for sending',
              notification_id: notification.id,
              record_id: result[:record]&.id
            }.to_json
          else
            status 500
            { status: 'error', message: result[:error] }.to_json
          end

        rescue => e
          logger.error("Endorsement error: #{e.class} - #{e.message}")
          status 500
          { status: 'error', message: e.message }.to_json
        end
      end

      # Helper endpoint to send review announcements
      # POST /coar_notify/outbox/announce-review
      post '/coar_notify/outbox/announce-review' do
        content_type :json

        begin
          params_hash = JSON.parse(request.body.read)

          # Build COAR Notify Review Announcement
          notification_json = {
            '@context': [
              'https://www.w3.org/ns/activitystreams',
              'https://purl.org/coar/notify'
            ],
            'id': params_hash['id'] || "urn:uuid:#{SecureRandom.uuid}",
            'type': ['Announce', 'coar-notify:ReviewAction'],
            'origin': {
              'id': params_hash['origin_id'] || CoarNotify.service_id,
              'inbox': params_hash['origin_inbox'] || CoarNotify.inbox_url,
              'type': 'Service'
            },
            'target': {
              'id': params_hash['target_id'],
              'inbox': params_hash['target_inbox'],
              'type': 'Service'
            },
            'object': {
              'id': params_hash['review_url'],
              'ietf:cite-as': params_hash['review_doi'],
              'type': params_hash['object_type'] || ['Page', 'sorg:Review']
            },
            'context': {
              'id': params_hash['preprint_doi'] || params_hash['preprint_url'],
              'type': params_hash['context_type'] || ['ScholarlyArticle']
            },
            'actor': {
              'id': params_hash['actor_id'] || CoarNotify.service_id,
              'name': params_hash['actor_name'] || 'NeuroLibre',
              'type': 'Service'
            }
          }

          notification = Coarnotify.from_hash(notification_json)
          sender = CoarNotify::Services::Sender.new
          # Pass the constructed JSON as payload
          result = sender.send_notification(notification, json_payload: notification_json.to_json)

          if result[:success]
            status 202
            {
              status: 'accepted',
              message: 'Review announcement queued for sending',
              notification_id: notification.id,
              record_id: result[:record]&.id
            }.to_json
          else
            status 500
            { status: 'error', message: result[:error] }.to_json
          end

        rescue => e
          logger.error("Review announcement error: #{e.class} - #{e.message}")
          status 500
          { status: 'error', message: e.message }.to_json
        end
      end
    end
  end
end
