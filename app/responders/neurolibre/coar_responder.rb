# frozen_string_literal: true

require_relative '../../lib/responder'
require_relative '../../coar_notify/coar_notify'

# CoarResponder handles bot commands for COAR Notify operations
#
# Commands:
#   @roboneuro coar request from <service>
#     - Send review request to specified service (e.g., prereview, pci)
#
#   @roboneuro coar status
#     - Show notification status for current issue
#
#   @roboneuro coar list
#     - List available COAR services
#
# Authorization: Typically restricted to editors
#
# Example:
#   @roboneuro coar request from prereview
#   > 🔄 Sending review request to prereview...
#   > ✅ Review request sent to PREreview. Notification ID: ...
module Neurolibre
class CoarResponder < Responder
  # Keyname for configuration (optional)
  keyname :neurolibre_coar

  def define_listening
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} coar\s+(\w+)(?:\s+from\s+(\w+))?\.?\s*$/i
  end

  def default_description
    [
      "Request a review from an external COAR Notify service",
      "Show the COAR notification history for this issue",
      "List the configured COAR Notify services"
    ]
  end

  def default_example_invocation
    [
      "@#{bot_name} coar request from prereview",
      "@#{bot_name} coar status",
      "@#{bot_name} coar list"
    ]
  end

  def process_message(message)
    # Check if COAR Notify is enabled
    unless CoarNotify.enabled?
      respond("ℹ️ COAR Notify is not enabled on this instance.")
      return
    end

    # Extract command and optional service name
    action = @match_data[1].downcase
    service_name = @match_data[2]&.downcase

    case action
    when 'request'
      handle_request(service_name)

    when 'status'
      handle_status

    when 'list'
      handle_list

    when 'help'
      handle_help

    else
      respond("❌ Unknown COAR command: `#{action}`\n\nUse `@#{bot_name} coar help` for available commands.")
    end
  end

  private

  # Handle: @roboneuro coar request from <service>
  def handle_request(service_name)
    unless service_name
      available = CoarNotify::Models::ServiceRegistry.service_names.join(', ')
      respond("❌ Please specify a service.\n\n**Usage:** `@#{bot_name} coar request from <service>`\n\n**Available services:** #{available}")
      return
    end

    # Validate service exists
    service_config = CoarNotify::Models::ServiceRegistry.get(service_name)

    unless service_config
      available = CoarNotify::Models::ServiceRegistry.service_names.join(', ')
      respond("❌ Unknown service: **#{service_name}**\n\n**Available services:** #{available}")
      return
    end

    # Enqueue send worker
    respond("🔄 Sending review request to **#{service_config['name']}**...\n\n_This may take a few moments._")
    CoarNotify::Workers::SendWorker.perform_async(@context.issue_id, service_name, 'request_review')
  end

  # Handle: @roboneuro coar status
  def handle_status
    notifications = CoarNotify::Models::Notification
                      .where(issue_id: @context.issue_id)
                      .reverse_order(:created_at)
                      .all

    if notifications.empty?
      respond("ℹ️ No COAR notifications found for this issue.")
      return
    end

    # Build status table
    message_parts = [
      "### COAR Notification Status",
      "",
      "| Direction | Type | Service | Status | Date |",
      "|-----------|------|---------|--------|------|"
    ]

    notifications.each do |n|
      direction_icon = n.direction == 'sent' ? '📤' : '📥'
      status_icon = case n.status
                    when 'processed' then '✅'
                    when 'failed' then '❌'
                    when 'processing' then '⏳'
                    else '⏸️'
                    end

      message_parts << "| #{direction_icon} #{n.direction.upcase} | #{n.primary_type} | #{n.service_name || 'N/A'} | #{status_icon} #{n.status} | #{n.created_at.strftime('%Y-%m-%d %H:%M')} |"
    end

    message_parts << ""
    message_parts << "_Total notifications: #{notifications.count}_"

    respond(message_parts.join("\n"))
  end

  # Handle: @roboneuro coar list
  def handle_list
    services = CoarNotify::Models::ServiceRegistry.all

    if services.empty?
      respond("ℹ️ No COAR services configured.")
      return
    end

    message_parts = [
      "### Available COAR Services",
      ""
    ]

    services.each do |key, config|
      message_parts << "**#{key}** - #{config['name']}"
      message_parts << "  - Supported patterns: #{config['supported_patterns'].join(', ')}"
      message_parts << ""
    end

    message_parts << "_To request a review:_ `@#{bot_name} coar request from <service>`"

    respond(message_parts.join("\n"))
  end

  # Handle: @roboneuro coar help
  def handle_help
    help_message = <<~HELP
      ### COAR Notify Commands

      **Request review from a service:**
      ```
      @#{bot_name} coar request from <service>
      ```
      Sends a review request to an external service (e.g., PREreview, PCI).

      **Check notification status:**
      ```
      @#{bot_name} coar status
      ```
      Shows all COAR notifications for this issue.

      **List available services:**
      ```
      @#{bot_name} coar list
      ```
      Lists all configured COAR services.

      ---

      **About COAR Notify:**
      COAR Notify is a protocol for linking repository-based preprints with external review and endorsement services using standardized notifications.

      Learn more: https://coar-notify.net
    HELP

    respond(help_message)
  end
end
end
