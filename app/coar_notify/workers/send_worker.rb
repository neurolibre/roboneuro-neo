# frozen_string_literal: true

require 'sidekiq'

module CoarNotify
  module Workers
    # Sidekiq worker for async sending of COAR Notify notifications
    #
    # This worker:
    # 1. Fetches paper data from neurolibre or GitHub issue
    # 2. Constructs and sends COAR notification
    # 3. Posts result to GitHub issue
    # 4. Handles errors with retry logic
    #
    # Retry strategy: 3 attempts with exponential backoff
    # Dead queue: Disabled (better to post error to GitHub than lose completely)
    #
    # Example usage:
    #   SendWorker.perform_async(issue_id, 'prereview', 'request_review')
    class SendWorker
      include Sidekiq::Worker
      sidekiq_options retry: 3, dead: false, queue: 'coar_notify'

      # Send a COAR notification
      #
      # @param issue_id [Integer] GitHub issue ID
      # @param service_name [String] target service name (e.g., 'prereview')
      # @param action [String] notification action ('request_review' or 'request_endorsement')
      def perform(issue_id, service_name, action = 'request_review')
        begin
          # Fetch paper data
          paper_data = fetch_paper_data(issue_id)

          unless paper_data
            post_error_to_github(
              issue_id,
              "❌ Could not fetch paper data for issue ##{issue_id}",
              "Unable to send COAR notification to #{service_name}."
            )
            return
          end

          # Validate service
          service_config = Models::ServiceRegistry.get(service_name)

          unless service_config
            available_services = Models::ServiceRegistry.service_names.join(', ')
            post_error_to_github(
              issue_id,
              "❌ Unknown COAR service: **#{service_name}**",
              "Available services: #{available_services}"
            )
            return
          end

          # Send notification based on action
          sender = Services::Sender.new

          result = case action
                   when 'request_review'
                     sender.send_request_review(paper_data, service_name)
                   when 'request_endorsement'
                     sender.send_request_endorsement(paper_data, service_name)
                   else
                     raise ArgumentError, "Unknown action: #{action}"
                   end

          # Post success to GitHub
          post_success_to_github(issue_id, result, service_config)

          logger.info("COAR Notify: Sent #{action} to #{service_name} for issue #{issue_id}")

        rescue Coarnotify::ValidationError => e
          # Validation error - don't retry, post error to GitHub
          error_details = format_validation_errors(e.errors)
          post_error_to_github(
            issue_id,
            "❌ COAR notification validation failed",
            "**Details:**\n```\n#{error_details}\n```"
          )

          logger.error("COAR Notify: Validation failed for issue #{issue_id}: #{error_details}")
          # Don't re-raise - no point retrying validation errors

        rescue Faraday::Error => e
          # Network error - Sidekiq will retry
          logger.error("COAR Notify: Network error sending to #{service_name}: #{e.message}")
          raise

        rescue => e
          # Unexpected error - post to GitHub and don't retry
          post_error_to_github(
            issue_id,
            "❌ COAR notification error",
            "**Error:** #{e.class}\n**Message:** #{e.message}"
          )

          logger.error("COAR Notify: Error sending notification: #{e.class} - #{e.message}")
          logger.error(e.backtrace.join("\n")) if e.backtrace
          # Don't re-raise - already posted error to GitHub
        end
      end

      private

      # Fetch paper data from neurolibre API
      #
      # @param issue_id [Integer] GitHub issue ID
      # @return [Hash, nil] paper data or nil if not found
      def fetch_paper_data(issue_id)
        Services::GitHubNotifier.get_paper_by_issue(issue_id)
      end

      # Post success message to GitHub
      #
      # @param issue_id [Integer] GitHub issue ID
      # @param result [Hash] send result from Sender service
      # @param service_config [Hash] service configuration
      def post_success_to_github(issue_id, result, service_config)
        service_display_name = service_config['name'] || result[:service]

        message = [
          "### ✅ COAR Notification Sent",
          "",
          "Successfully sent review request to **#{service_display_name}**.",
          "",
          "<details>",
          "<summary>Notification Details</summary>",
          "",
          "**Notification ID:** `#{result[:notification_id]}`",
          "",
          "**Response Status:** #{result[:response_action]}",
          "",
          result[:response_location] ? "**Location:** #{result[:response_location]}" : nil,
          "",
          "_This notification was sent via the COAR Notify protocol._",
          "",
          "The service may respond with an acceptance or rejection notification.",
          "</details>"
        ].compact.join("\n")

        Services::GitHubNotifier.post_comment(issue_id, message)
      end

      # Post error message to GitHub
      #
      # @param issue_id [Integer] GitHub issue ID
      # @param title [String] error title
      # @param details [String] error details
      def post_error_to_github(issue_id, title, details)
        message = [
          "### #{title}",
          "",
          details,
          "",
          "_If this error persists, please contact the editorial team._"
        ].join("\n")

        Services::GitHubNotifier.post_comment(issue_id, message)
      end

      # Format validation errors for display
      #
      # @param errors [Hash] validation errors from coarnotifyrb
      # @return [String] formatted error string
      def format_validation_errors(errors)
        return errors.to_s unless errors.is_a?(Hash)

        errors.map do |field, error_info|
          if error_info.is_a?(Hash)
            field_errors = error_info['errors'] || []
            "#{field}: #{field_errors.join(', ')}"
          else
            "#{field}: #{error_info}"
          end
        end.join("\n")
      end
    end
  end
end
