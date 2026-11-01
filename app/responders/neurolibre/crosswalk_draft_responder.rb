require_relative "../../lib/responder"
require_relative "../../lib/neurolibre_server_command"

module Neurolibre
class CrosswalkDraftResponder < Responder
  include NeurolibreServerCommand

  keyname :neurolibre_crosswalk_draft

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} crosswalk draft\.?[ \t\r]*$/i
  end

  def process_message(message)
    unless sent_by?(:editor, :reviewer)
      respond("Only the issue's editor or a reviewer can ask for `@#{bot_name} crosswalk draft`.")
      return
    end
    send_to_server
  end

  def default_description
    "Draft the paper's crosswalk, the mapping of each file and column of its data onto the shared vocabulary " \
      "with the passages that say so, and post it here for review."
  end

  def default_example_invocation
    "@#{bot_name} crosswalk draft"
  end
end
end
