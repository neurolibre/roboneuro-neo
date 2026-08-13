# frozen_string_literal: true

require 'coarnotify'

module CoarNotify
  module Services
    # Processor service for handling received COAR Notify notifications
    #
    # This service processes different notification types and triggers
    # appropriate actions (GitHub comments, neurolibre updates, etc.)
    #
    # Supported notification types:
    # - Accept: Service accepted a review request
    # - Reject: Service rejected a review request
    # - AnnounceReview: Review has been published
    # - AnnounceEndorsement: Endorsement has been published
    # - TentativelyAccept/TentativelyReject: Provisional responses
    #
    # Example usage:
    #   processor = Processor.new
    #   processor.process(notification, record)
    class Processor
      # Process a notification based on its type
      #
      # @param notification [Coarnotify::Patterns::*] coarnotifyrb notification object
      # @param record [Models::Notification] database record
      def process(notification, record)
        case notification
        when Coarnotify::Patterns::Accept
          process_accept(notification, record)

        when Coarnotify::Patterns::Reject
          process_reject(notification, record)

        when Coarnotify::Patterns::TentativelyAccept
          process_tentatively_accept(notification, record)

        when Coarnotify::Patterns::TentativelyReject
          process_tentatively_reject(notification, record)

        when Coarnotify::Patterns::AnnounceReview
          process_announce_review(notification, record)

        when Coarnotify::Patterns::AnnounceEndorsement
          process_announce_endorsement(notification, record)

        else
          process_unknown(notification, record)
        end
      end

      private

      # Process Accept notification
      def process_accept(notification, record)
        service_name = record.service_name || 'External service'

        message = build_message(
          title: "✅ #{service_name.capitalize} accepted the review request",
          notification_id: notification.id,
          summary: notification.summary
        )

        post_to_github(record, message)
      end

      # Process Reject notification
      def process_reject(notification, record)
        service_name = record.service_name || 'External service'

        message = build_message(
          title: "❌ #{service_name.capitalize} declined the review request",
          notification_id: notification.id,
          summary: notification.summary,
          details: "The service has declined to review this preprint."
        )

        post_to_github(record, message)
      end

      # Process TentativelyAccept notification
      def process_tentatively_accept(notification, record)
        service_name = record.service_name || 'External service'

        message = build_message(
          title: "🟡 #{service_name.capitalize} tentatively accepted the review request",
          notification_id: notification.id,
          summary: notification.summary,
          details: "The service has provisionally accepted. Awaiting confirmation."
        )

        post_to_github(record, message)
      end

      # Process TentativelyReject notification
      def process_tentatively_reject(notification, record)
        service_name = record.service_name || 'External service'

        message = build_message(
          title: "🟡 #{service_name.capitalize} tentatively declined the review request",
          notification_id: notification.id,
          summary: notification.summary
        )

        post_to_github(record, message)
      end

      # Process AnnounceReview notification
      def process_announce_review(notification, record)
        service_name = record.service_name || 'External service'
        review_url = notification.object&.id

        unless review_url
          warn "COAR Notify: AnnounceReview missing object.id (review URL)"
          return
        end

        message = build_message(
          title: "📝 Review published by #{service_name.capitalize}",
          notification_id: notification.id,
          summary: notification.summary,
          details: "Review URL: #{review_url}"
        )

        # Post to GitHub
        post_to_github(record, message)

        # Store review link in neurolibre
        if record.paper_doi
          GitHubNotifier.update_paper_metadata(record.paper_doi, {
            service: service_name,
            review_url: review_url,
            notification_id: notification.id,
            received_at: Time.now.iso8601
          })
        end
      end

      # Process AnnounceEndorsement notification
      def process_announce_endorsement(notification, record)
        service_name = record.service_name || 'External service'
        endorsement_url = notification.object&.id

        unless endorsement_url
          warn "COAR Notify: AnnounceEndorsement missing object.id (endorsement URL)"
          return
        end

        message = build_message(
          title: "⭐ Endorsement published by #{service_name.capitalize}",
          notification_id: notification.id,
          summary: notification.summary,
          details: "Endorsement URL: #{endorsement_url}"
        )

        # Post to GitHub
        post_to_github(record, message)

        # Store endorsement in neurolibre
        if record.paper_doi
          GitHubNotifier.update_paper_metadata(record.paper_doi, {
            service: service_name,
            endorsement_url: endorsement_url,
            notification_id: notification.id,
            received_at: Time.now.iso8601
          })
        end
      end

      # Process unknown notification type
      def process_unknown(notification, record)
        warn "COAR Notify: Unknown notification type: #{notification.type}"

        message = build_message(
          title: "ℹ️ COAR Notification received",
          notification_id: notification.id,
          summary: notification.summary,
          details: "Type: #{Array(notification.type).join(', ')}"
        )

        post_to_github(record, message)
      end

      # Build formatted GitHub comment message
      #
      # @param title [String] message title
      # @param notification_id [String] COAR notification ID
      # @param summary [String, nil] notification summary
      # @param details [String, nil] additional details
      # @return [String] formatted markdown message
      def build_message(title:, notification_id:, summary: nil, details: nil)
        parts = []
        parts << "### #{title}"
        parts << ""
        parts << summary if summary
        parts << details if details
        parts << ""
        parts << "<details>"
        parts << "<summary>Notification Details</summary>"
        parts << ""
        parts << "**Notification ID:** `#{notification_id}`"
        parts << ""
        parts << "_This notification was received via the COAR Notify protocol._"
        parts << "</details>"

        parts.join("\n")
      end

      # Post message to GitHub issue
      #
      # @param record [Models::Notification] notification record
      # @param message [String] message to post
      def post_to_github(record, message)
        issue_id = find_issue_id(record)

        if issue_id
          GitHubNotifier.post_comment(issue_id, message)
        else
          warn "COAR Notify: Could not find issue ID for notification #{record.id}"
        end
      end

      # Find GitHub issue ID for a notification
      #
      # @param record [Models::Notification] notification record
      # @return [Integer, nil] issue ID or nil if not found
      def find_issue_id(record)
        # Strategy 1: Already stored in record
        return record.issue_id if record.issue_id

        # Strategy 2: Find from sent notification via inReplyTo
        if record.in_reply_to
          sent = Models::Notification.where(
            notification_id: record.in_reply_to,
            direction: 'sent'
          ).first

          return sent.issue_id if sent&.issue_id
        end

        # Strategy 3: Query neurolibre API by DOI
        if record.paper_doi
          issue_id = GitHubNotifier.get_issue_by_doi(record.paper_doi)

          # Update record with found issue_id for future use
          record.update(issue_id: issue_id) if issue_id

          return issue_id
        end

        nil
      end
    end
  end
end
