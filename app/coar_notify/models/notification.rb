# frozen_string_literal: true

require 'sequel'
require 'coarnotify'

module CoarNotify
  module Models
    # Notification model for persisting COAR Notify notifications
    #
    # This model stores both sent (outbox) and received (inbox) notifications
    # in compliance with W3C LDN and COAR Notify specifications.
    #
    # Example usage:
    #   # Create from received notification
    #   notification = Notification.create_from_coar(coar_obj, 'received')
    #
    #   # Query notifications
    #   Notification.received.pending.all
    #   Notification.for_paper('10.55458/neurolibre.00027').all
    class Notification < Sequel::Model(:coar_notifications)
      # Use the shared database connection from CoarNotify module
      def self.db
        CoarNotify.database
      end

      plugin :timestamps, update_on_create: true

      # Scopes for common queries
      dataset_module do
        # Get received notifications (inbox)
        def received
          where(direction: 'received')
        end

        # Get sent notifications (outbox)
        def sent
          where(direction: 'sent')
        end

        # Get pending notifications
        def pending
          where(status: 'pending')
        end

        # Get processing notifications
        def processing
          where(status: 'processing')
        end

        # Get processed notifications
        def processed
          where(status: 'processed')
        end

        # Get failed notifications
        def failed
          where(status: 'failed')
        end

        # Get notifications for a specific paper DOI
        def for_paper(doi)
          where(paper_doi: doi)
        end

        # Get notifications by service
        def by_service(service_name)
          where(service_name: service_name)
        end

        # Get recent notifications
        def recent(limit: 100)
          reverse_order(:created_at).limit(limit)
        end

        # Get notifications by type
        def by_type(notification_type)
          where(Sequel.pg_array(:notification_types).contains([notification_type]))
        end
      end

      # Validations - all manual to avoid Sequel validation helper bugs
      def validate
        super
        # Manual presence validations
        errors.add(:notification_id, 'cannot be blank') if !notification_id || notification_id.to_s.strip.empty?
        errors.add(:direction, 'cannot be blank') if !direction || direction.to_s.strip.empty?
        errors.add(:notification_types, 'cannot be blank') if !notification_types || notification_types.empty?
        errors.add(:origin_id, 'cannot be blank') if !origin_id || origin_id.to_s.strip.empty?
        errors.add(:target_id, 'cannot be blank') if !target_id || target_id.to_s.strip.empty?
        errors.add(:object_id, 'cannot be blank') if !object_id || object_id.to_s.strip.empty?
        errors.add(:payload, 'cannot be blank') if !payload || payload.to_s.strip.empty?
        errors.add(:status, 'cannot be blank') if !status || status.to_s.strip.empty?
        # Validate direction is one of allowed values
        if direction && !['sent', 'received'].include?(direction)
          errors.add(:direction, 'must be sent or received')
        end
        # Validate status is one of allowed values
        if status && !['pending', 'processing', 'processed', 'failed', 'cancelled'].include?(status)
          errors.add(:status, 'must be pending, processing, processed, failed, or cancelled')
        end
        # Check uniqueness manually (notification_id must be unique per direction)
        if new? && notification_id && direction
          existing = self.class.where(notification_id: notification_id, direction: direction).count
          if existing > 0
            errors.add(:notification_id, 'is already taken for this direction')
          end
        end
      end

      # Parse stored payload back to coarnotifyrb object
      # @return [Coarnotify::Patterns::*] coarnotifyrb notification object
      def to_coar_object
        Coarnotify.from_hash(payload)
      end

      # Get human-readable notification type
      # @return [String] primary notification type
      def primary_type
        notification_types.last # COAR patterns typically have base type last
      end

      # Check if notification is of a specific type
      # @param type [String] notification type to check
      # @return [Boolean]
      def type?(type)
        notification_types.include?(type)
      end

      # Mark notification as processing
      def mark_processing!
        update(status: 'processing', updated_at: Time.now)
      end

      # Mark notification as processed
      def mark_processed!
        update(
          status: 'processed',
          processed_at: Time.now,
          updated_at: Time.now,
          error_message: nil
        )
      end

      # Mark notification as failed
      # @param error [String, Exception] error message or exception
      def mark_failed!(error)
        error_msg = error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s
        update(
          status: 'failed',
          error_message: error_msg,
          updated_at: Time.now
        )
      end

      # Mark notification as cancelled
      #
      # Only meaningful for work that has not started. Cancelling is a
      # terminal state: it does not stop an in-flight worker.
      def mark_cancelled!
        update(status: 'cancelled', updated_at: Time.now)
      end

      # Whether this notification can be retried from the dashboard
      #
      # Only failed work is retryable. Retrying something already processed
      # would send a duplicate notification to a remote service.
      #
      # @return [Boolean]
      def retryable?
        status == 'failed'
      end

      # Whether this notification can be cancelled from the dashboard
      #
      # Only work that has not been picked up yet. Once a worker has it,
      # cancelling the record would misreport what actually happened.
      #
      # @return [Boolean]
      def cancellable?
        status == 'pending'
      end

      # The SendWorker action implied by this notification's type
      #
      # @return [String] 'request_endorsement' or 'request_review'
      def send_action
        primary_type.to_s.include?('Endorsement') ? 'request_endorsement' : 'request_review'
      end

      # Class methods for creating notifications
      class << self
        # Create notification record from coarnotifyrb object
        # @param notification [Coarnotify::Patterns::*] coarnotifyrb notification
        # @param direction [String] 'sent' or 'received'
        # @param extra_attrs [Hash] additional attributes (issue_id, etc.)
        # @return [Notification] created record
        def create_from_coar(notification, direction, extra_attrs = {})
          # Extract types - Sequel will handle array serialization automatically
          notif_types = extract_types(notification.type)
          obj_types = extract_types(notification.object&.type)
          ctx_types = extract_types(notification.context&.type)

          # Use provided JSON payload if available, otherwise parse notification
          # Pass hash directly - Sequel will serialize to JSONB automatically
          payload = if extra_attrs[:json_payload]
                      JSON.parse(extra_attrs.delete(:json_payload))
                    else
                      parse_payload(notification)
                    end

          create(
            notification_id: notification.id,
            direction: direction,
            notification_types: notif_types,
            origin_id: notification.origin.id,
            origin_inbox: notification.origin&.inbox,
            target_id: notification.target.id,
            target_inbox: notification.target&.inbox,
            object_id: notification.object.id,
            object_type: obj_types ? obj_types.join(', ') : nil,  # TEXT column, not array
            context_id: notification.context&.id,
            context_type: ctx_types ? ctx_types.join(', ') : nil,  # TEXT column, not array
            in_reply_to: (notification.respond_to?(:in_reply_to) ? notification.in_reply_to : nil),
            actor_id: notification.actor&.id,
            actor_name: notification.actor&.name,
            summary: (notification.respond_to?(:summary) ? notification.summary : nil),
            payload: payload,
            paper_doi: extract_paper_doi(notification),
            service_name: extract_service_name(notification, direction),
            status: extra_attrs[:status] || 'pending',
            issue_id: extra_attrs[:issue_id],
            created_at: Time.now,
            updated_at: Time.now
          )
        end

        # Extract paper DOI from notification
        # @param notification [Coarnotify::Patterns::*] coarnotifyrb notification
        # @return [String, nil] extracted DOI or nil
        def extract_paper_doi(notification)
          # Try object.id first (usually the preprint DOI)
          doi_url = notification.object&.id || notification.context&.id
          return nil unless doi_url

          # Extract DOI pattern (e.g., "10.55458/neurolibre.00027")
          match = doi_url.match(%r{(10\.\d+/[\w\.\-]+)})
          match ? match[1] : nil
        end

        # Extract service name from notification
        # @param notification [Coarnotify::Patterns::*] coarnotifyrb notification
        # @param direction [String] 'sent' or 'received'
        # @return [String, nil] service name or nil
        def extract_service_name(notification, direction)
          service_id = if direction == 'sent'
                         notification.target&.id
                       else
                         notification.origin&.id
                       end

          return nil unless service_id

          ServiceRegistry.name_from_id(service_id) || service_id
        end

        private

        # Extract types from coarnotify type object to array of strings
        # @param type_obj [Object] type object from coarnotify
        # @return [Array<String>, nil] array of type strings or nil
        def extract_types(type_obj)
          return nil if type_obj.nil?

          # If it's already an array of strings, return it
          return type_obj if type_obj.is_a?(Array) && type_obj.all? { |t| t.is_a?(String) }

          # If it's a single string, wrap in array
          return [type_obj] if type_obj.is_a?(String)

          # If it responds to to_a, convert to array
          if type_obj.respond_to?(:to_a)
            types = type_obj.to_a
            return types.map(&:to_s) if types.is_a?(Array)
          end

          # Try to get the value if it's a wrapper object
          if type_obj.respond_to?(:value)
            return extract_types(type_obj.value)
          end

          # Fallback: convert to string and wrap in array
          [type_obj.to_s]
        end

        # Parse notification to JSON hash
        # @param notification [Coarnotify::Patterns::*] coarnotifyrb notification
        # @return [Hash] JSON-compatible hash
        def parse_payload(notification)
          json_string = notification.to_json
          JSON.parse(json_string)
        rescue JSON::ParserError, NoMethodError => e
          # Log the error for debugging
          warn "Failed to parse notification to JSON: #{e.class} - #{e.message}"
          warn "Notification class: #{notification.class}"

          # Fallback: use notification's internal hash representation
          properties = notification.instance_variable_get(:@properties) || {}

          # If properties is still empty, try to extract basic structure
          if properties.empty?
            {
              'id' => notification.respond_to?(:id) ? notification.id : nil,
              'type' => notification.respond_to?(:type) ? notification.type : nil,
              'error' => 'Failed to serialize notification to JSON'
            }
          else
            properties
          end
        end
      end
    end
  end
end
