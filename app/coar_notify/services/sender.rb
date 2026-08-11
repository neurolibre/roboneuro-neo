# frozen_string_literal: true

require 'coarnotify'
require 'securerandom'

module CoarNotify
  module Services
    # Sender service for sending COAR Notify notifications (outbox)
    #
    # This service constructs and sends notifications to external services
    # according to COAR Notify patterns. It handles:
    # - Building notification payloads
    # - Sending via coarnotifyrb client
    # - Persisting sent notifications to database
    #
    # Supported patterns:
    # - RequestReview: Request review of a preprint
    # - RequestEndorsement: Request endorsement of a preprint
    # - Generic: Send any COAR Notify notification
    #
    # Example usage:
    #   sender = Sender.new
    #   result = sender.send_request_review(paper_data, 'prereview')
    #   result = sender.send_notification(notification)
    class Sender
      # Send a generic COAR Notify notification
      #
      # @param notification [Coarnotify::Patterns::*] notification object from coarnotifyrb
      # @param extra_attrs [Hash] optional attributes (issue_id, json_payload, etc.)
      # @option extra_attrs [String] :json_payload original JSON string (optional but recommended)
      # @return [Hash] result with success status and notification details
      def send_notification(notification, extra_attrs = {})
        # Validate notification
        notification.validate

        # Get target inbox URL
        inbox_url = notification.target&.inbox
        raise ArgumentError, 'Notification target inbox is required' unless inbox_url

        # Create COAR Notify client
        client = Coarnotify.client(inbox_url: inbox_url)

        # Send notification
        begin
          response = client.send(notification, validate: true)

          # Persist to database
          record = Models::Notification.create_from_coar(
            notification,
            'sent',
            extra_attrs.merge(status: 'processed') # Sent notifications are immediately 'processed'
          )

          {
            success: true,
            notification_id: notification.id,
            response_action: response.action,
            response_location: response.location,
            record: record,
            record_id: record.id
          }
        rescue Coarnotify::NotifyException => e
          # Handle HTTP 200 (idempotent) as success
          # The notification was already received, which is fine
          if e.message.include?('200')
            # Still persist to database as sent
            begin
              record = Models::Notification.create_from_coar(
                notification,
                'sent',
                extra_attrs.merge(status: 'processed')
              )

              return {
                success: true,
                notification_id: notification.id,
                response_action: 'already_received',
                record: record,
                record_id: record.id
              }
            rescue => db_error
              # If we can't save to DB, log it but still return success
              # since the notification WAS successfully sent/received
              warn "Successfully sent notification but failed to persist: #{db_error.message}"
              warn "Notification ID: #{notification.id}"

              return {
                success: true,
                notification_id: notification.id,
                response_action: 'already_received',
                warning: 'Notification sent but not persisted to database'
              }
            end
          end

          # For other NotifyException errors, treat as failure
          error_msg = "Failed to send notification: #{e.class} - #{e.message}"

          # Try to persist failed notification with original JSON payload
          begin
            # Get the original JSON from the request that was sent
            original_json = notification.to_json

            record = Models::Notification.create_from_coar(
              notification,
              'sent',
              extra_attrs.merge(
                status: 'failed',
                error_message: error_msg,
                json_payload: original_json
              )
            )
          rescue => db_error
            # If we can't even save to DB, just log it
            warn "Failed to persist failed notification: #{db_error.message}"
          end

          {
            success: false,
            error: error_msg,
            notification_id: notification.id,
            record: record
          }
        rescue => e
          # Log error and return failure
          error_msg = "Failed to send notification: #{e.class} - #{e.message}"

          # Try to persist failed notification
          begin
            # Get the original JSON from the request that was sent
            original_json = notification.to_json

            record = Models::Notification.create_from_coar(
              notification,
              'sent',
              extra_attrs.merge(
                status: 'failed',
                error_message: error_msg,
                json_payload: original_json
              )
            )
          rescue => db_error
            # If we can't even save to DB, just log it
            warn "Failed to persist failed notification: #{db_error.message}"
          end

          {
            success: false,
            error: error_msg,
            notification_id: notification.id,
            record: record
          }
        end
      end

      # Send a RequestReview notification
      #
      # @param paper_data [Hash] paper metadata
      # @option paper_data [String] :doi paper DOI
      # @option paper_data [Integer] :issue_id GitHub issue ID
      # @option paper_data [String] :repository_url GitHub repository URL
      # @option paper_data [String] :url preprint URL
      # @option paper_data [String] :title paper title
      # @option paper_data [String] :editor_orcid editor's ORCID (optional)
      # @option paper_data [String] :editor_name editor's name (optional)
      # @param service_name [String] target service name (e.g., 'prereview')
      # @return [Hash] result with success status and notification details
      # @raise [ArgumentError] if service is unknown or required data is missing
      def send_request_review(paper_data, service_name)
        # Validate service
        service_config = Models::ServiceRegistry.get(service_name)
        raise ArgumentError, "Unknown service: #{service_name}" unless service_config

        # Validate required paper data
        validate_paper_data!(paper_data, [:doi, :issue_id])

        # Create COAR Notify client
        client = Coarnotify.client(inbox_url: service_config['inbox_url'])

        # Build RequestReview notification
        notification = build_request_review(paper_data, service_config)

        # Validate notification
        notification.validate

        # Send notification
        begin
          response = client.send(notification, validate: true)

          # Persist to database
          record = Models::Notification.create_from_coar(
            notification,
            'sent',
            issue_id: paper_data[:issue_id],
            status: 'processed' # Sent notifications are immediately 'processed'
          )

          {
            success: true,
            notification_id: notification.id,
            response_action: response.action,
            response_location: response.location,
            record_id: record.id,
            service: service_name
          }
        rescue Coarnotify::NotifyException => e
          # Handle HTTP 200 (idempotent) as success
          if e.message.include?('200')
            record = Models::Notification.create_from_coar(
              notification,
              'sent',
              issue_id: paper_data[:issue_id],
              status: 'processed'
            )

            return {
              success: true,
              notification_id: notification.id,
              response_action: 'already_received',
              record_id: record.id,
              service: service_name
            }
          end

          # For other errors, re-raise
          raise
        end
      end

      # Send a RequestEndorsement notification
      #
      # @param paper_data [Hash] paper metadata (same as send_request_review)
      # @param service_name [String] target service name
      # @return [Hash] result with success status and notification details
      def send_request_endorsement(paper_data, service_name)
        # Validate service
        service_config = Models::ServiceRegistry.get(service_name)
        raise ArgumentError, "Unknown service: #{service_name}" unless service_config

        # Validate required paper data
        validate_paper_data!(paper_data, [:doi, :issue_id])

        # Create client
        client = Coarnotify.client(inbox_url: service_config['inbox_url'])

        # Build RequestEndorsement notification
        notification = build_request_endorsement(paper_data, service_config)

        # Validate and send
        notification.validate

        begin
          response = client.send(notification, validate: true)

          # Persist to database
          record = Models::Notification.create_from_coar(
            notification,
            'sent',
            issue_id: paper_data[:issue_id],
            status: 'processed'
          )

          {
            success: true,
            notification_id: notification.id,
            response_action: response.action,
            response_location: response.location,
            record_id: record.id,
            service: service_name
          }
        rescue Coarnotify::NotifyException => e
          # Handle HTTP 200 (idempotent) as success
          if e.message.include?('200')
            record = Models::Notification.create_from_coar(
              notification,
              'sent',
              issue_id: paper_data[:issue_id],
              status: 'processed'
            )

            return {
              success: true,
              notification_id: notification.id,
              response_action: 'already_received',
              record_id: record.id,
              service: service_name
            }
          end

          # For other errors, re-raise
          raise
        end
      end

      private

      # Build RequestReview notification
      #
      # @param paper_data [Hash] paper metadata
      # @param service_config [Hash] service configuration
      # @return [Coarnotify::Patterns::RequestReview] notification object
      def build_request_review(paper_data, service_config)
        notification = Coarnotify::Patterns::RequestReview.new

        # Generate unique notification ID
        notification_uuid = SecureRandom.uuid
        notification.id = "#{CoarNotify.inbox_url}/notifications/#{notification_uuid}"

        # Set origin (NeuroLibre via roboneuro)
        notification.origin = Coarnotify::Core::Notify::NotifyService.new
        notification.origin.id = CoarNotify.service_id
        notification.origin.inbox = CoarNotify.inbox_url

        # Set target (review service)
        notification.target = Coarnotify::Core::Notify::NotifyService.new
        notification.target.id = service_config['id']
        notification.target.inbox = service_config['inbox_url']

        # Set object (the preprint being reviewed)
        notification.object = Coarnotify::Patterns::RequestReviewObject.new
        notification.object.id = "https://doi.org/#{paper_data[:doi]}"
        notification.object.cite_as = "https://doi.org/#{paper_data[:doi]}"
        notification.object.type = ["ScholarlyArticle"]

        # Add item (repository or preprint URL)
        item = Coarnotify::Patterns::RequestReviewItem.new
        item.id = paper_data[:repository_url] || paper_data[:url] || notification.object.id
        item.media_type = "text/html"
        item.type = "WebPage"
        notification.object.item = item

        # Set actor (editor, if available)
        if paper_data[:editor_orcid] || paper_data[:editor_name]
          notification.actor = Coarnotify::Core::Notify::NotifyActor.new
          notification.actor.id = "https://orcid.org/#{paper_data[:editor_orcid]}" if paper_data[:editor_orcid]
          notification.actor.name = paper_data[:editor_name] if paper_data[:editor_name]
          notification.actor.type = "Person"
        end

        notification
      end

      # Build RequestEndorsement notification
      #
      # @param paper_data [Hash] paper metadata
      # @param service_config [Hash] service configuration
      # @return [Coarnotify::Patterns::RequestEndorsement] notification object
      def build_request_endorsement(paper_data, service_config)
        notification = Coarnotify::Patterns::RequestEndorsement.new

        # Generate unique notification ID
        notification_uuid = SecureRandom.uuid
        notification.id = "#{CoarNotify.inbox_url}/notifications/#{notification_uuid}"

        # Set origin
        notification.origin = Coarnotify::Core::Notify::NotifyService.new
        notification.origin.id = CoarNotify.service_id
        notification.origin.inbox = CoarNotify.inbox_url

        # Set target
        notification.target = Coarnotify::Core::Notify::NotifyService.new
        notification.target.id = service_config['id']
        notification.target.inbox = service_config['inbox_url']

        # Set object
        notification.object = Coarnotify::Core::Notify::NotifyObject.new
        notification.object.id = "https://doi.org/#{paper_data[:doi]}"
        notification.object.cite_as = "https://doi.org/#{paper_data[:doi]}"
        notification.object.type = ["ScholarlyArticle"]

        # Set actor
        if paper_data[:editor_orcid] || paper_data[:editor_name]
          notification.actor = Coarnotify::Core::Notify::NotifyActor.new
          notification.actor.id = "https://orcid.org/#{paper_data[:editor_orcid]}" if paper_data[:editor_orcid]
          notification.actor.name = paper_data[:editor_name] if paper_data[:editor_name]
          notification.actor.type = "Person"
        end

        notification
      end

      # Validate required paper data fields
      #
      # @param paper_data [Hash] paper data to validate
      # @param required_fields [Array<Symbol>] required field names
      # @raise [ArgumentError] if any required field is missing
      def validate_paper_data!(paper_data, required_fields)
        missing = required_fields.select { |field| paper_data[field].nil? || paper_data[field].to_s.empty? }

        unless missing.empty?
          raise ArgumentError, "Missing required paper data: #{missing.join(', ')}"
        end
      end
    end
  end
end
