require_relative "../../lib/responder"
require_relative "../../lib/neurolibre_server_command"

module Neurolibre
class WeftCheckResponder < Responder
  include NeurolibreServerCommand

  keyname :neurolibre_weft_check

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} weft check(?:[ \t]+at[ \t]+(\d+))?\.?[ \t\r]*$/i
  end

  def process_message(message)
    unless sent_by?(:author, :editor, :reviewer)
      respond("Only the paper's author, the issue's editor or a reviewer can ask for `@#{bot_name} weft check`.")
      return
    end
    at = match_data && match_data[1]
    send_to_server(at: at && at.to_i)
  end

  def default_description
    "Check the description of the paper's data, with the corrections in this comment (or in the comment named " \
    "with `at`) applied."
  end

  def default_example_invocation
    "@#{bot_name} weft check"
  end
end
end
