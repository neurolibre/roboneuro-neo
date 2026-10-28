require_relative "../../lib/responder"
require_relative "../../lib/neurolibre_server_command"

module Neurolibre
class WeftDraftResponder < Responder
  include NeurolibreServerCommand

  keyname :neurolibre_weft_draft

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} weft draft\.?[ \t\r]*$/i
  end

  def process_message(message)
    unless sent_by?(:editor, :reviewer)
      respond("Only the issue's editor or a reviewer can ask for `@#{bot_name} weft draft`.")
      return
    end
    send_to_server
  end

  def default_description
    "Describe the paper's data: draft its description and post it here for review."
  end

  def default_example_invocation
    "@#{bot_name} weft draft"
  end
end
end
