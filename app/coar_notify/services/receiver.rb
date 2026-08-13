# frozen_string_literal: true

require 'coarnotify'
require 'json'

module CoarNotify
  module Services
    # Receiver service for handling incoming COAR Notify notifications
    #
    # This service implements W3C LDN receiver functionality:
    # - Validates incoming notifications
    # - Persists to database
    # - Enqueues async processing
    # - Provides GET endpoint for listing notifications
    #
    # Example usage:
    #   receiver = Receiver.new
    #   result = receiver.receive(json_body, request_ip: '1.2.3.4')
    class Receiver
      # ServiceBinding for coarnotifyrb server
      class ServiceBinding < Coarnotify::Server::COARNotifyServiceBinding
        def notification_received(notification)
          # Return receipt immediately (actual processing happens in worker)
          Coarnotify::Server::COARNotifyReceipt.new(
            Coarnotify::Server::COARNotifyReceipt::CREATED,
            notification.id
          )
        end
      end

      def initialize
        @server = Coarnotify.server(ServiceBinding.new)
      end

      # Receive and persist incoming notification
      #
      # @param json_body [String] JSON-LD notification body
      # @param request_ip [String, nil] IP address of sender (for whitelist validation)
      # @return [Hash] result with :status, :location, :record_id
      # @raise [SecurityError] if IP whitelist validation fails
      # @raise [Coarnotify::ValidationError] if notification is invalid
      def receive(json_body, request_ip: nil)
        # 1. Validate IP if whitelist enabled
        validate_ip!(request_ip) if CoarNotify.ip_whitelist_enabled?

        # 2. Parse and validate with coarnotifyrb
        # First parse to get the notification object
        notification = Coarnotify.from_json(json_body)

        # Validate manually to get detailed errors
        begin
          notification.validate
        rescue Coarnotify::ValidationError => e
          # Re-raise with detailed validation errors
          raise e
        end

        # Process through server for receipt
        receipt = @server.receive(json_body, validate: true)

        # 3. Check for duplicate (idempotency)
        existing = Models::Notification.where(
          notification_id: notification.id
        ).first

        if existing
          return {
            status: :ok,
            message: 'Notification already received',
            location: existing.notification_id,
            record_id: existing.id
          }
        end

        # 4. Persist to database (pass original JSON for payload)
        record = Models::Notification.create_from_coar(
          notification,
          'received',
          json_payload: json_body
        )

        # 5. Enqueue worker for async processing
        Workers::ReceiveWorker.perform_async(record.id)

        # 6. Return success
        {
          status: :created,
          location: notification.id,
          record_id: record.id
        }
      end

      # List all received notifications (W3C LDN GET /inbox)
      #
      # @param limit [Integer] maximum number of notifications to return
      # @param offset [Integer] offset for pagination
      # @return [Array<Models::Notification>] list of notifications
      def list_notifications(limit: 100, offset: 0)
        Models::Notification
          .received
          .reverse_order(:created_at)
          .limit(limit)
          .offset(offset)
          .all
      end

      # Get specific notification by ID
      #
      # @param notification_id [String] notification ID
      # @return [Models::Notification, nil] notification or nil if not found
      def get_notification(notification_id)
        Models::Notification.where(
          notification_id: notification_id,
          direction: 'received'
        ).first
      end

      private

      # Validate request IP against whitelist
      #
      # @param ip [String] IP address to validate
      # @raise [SecurityError] if IP is not in whitelist
      def validate_ip!(ip)
        return if ENV['RACK_ENV'] == 'development' # Skip in development

        allowed_ips = CoarNotify.allowed_ips

        unless allowed_ips.include?(ip)
          raise SecurityError, "Unauthorized IP: #{ip}"
        end
      end
    end
  end
end
