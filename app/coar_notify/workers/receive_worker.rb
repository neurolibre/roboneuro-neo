# frozen_string_literal: true

require 'sidekiq'

module CoarNotify
  module Workers
    # Sidekiq worker for async processing of received COAR Notify notifications
    #
    # This worker:
    # 1. Fetches notification from database
    # 2. Processes it based on type (Accept, AnnounceReview, etc.)
    # 3. Posts results to GitHub and/or neurolibre
    # 4. Marks notification as processed or failed
    #
    # Retry strategy: 3 attempts with exponential backoff
    #
    # Example usage:
    #   ReceiveWorker.perform_async(notification_record_id)
    class ReceiveWorker
      include Sidekiq::Worker
      sidekiq_options retry: 3, queue: 'coar_notify'

      # Process a received notification
      #
      # @param notification_record_id [Integer] database record ID
      def perform(notification_record_id)
        record = Models::Notification[notification_record_id]

        unless record
          logger.warn("COAR Notify: Notification record #{notification_record_id} not found")
          return
        end

        # Check if already processed (idempotency)
        if record.status == 'processed'
          logger.info("COAR Notify: Notification #{record.id} already processed, skipping")
          return
        end

        # Mark as processing
        record.mark_processing!

        begin
          # Parse notification from stored payload
          notification = record.to_coar_object

          # Process based on notification type
          processor = Services::Processor.new
          processor.process(notification, record)

          # Mark as processed
          record.mark_processed!

          logger.info("COAR Notify: Successfully processed notification #{record.id} (#{record.primary_type})")

        rescue => e
          # Mark as failed
          record.mark_failed!(e)

          logger.error("COAR Notify: Failed to process notification #{record.id}: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n")) if e.backtrace

          # Re-raise for Sidekiq retry mechanism
          raise
        end
      end
    end
  end
end
