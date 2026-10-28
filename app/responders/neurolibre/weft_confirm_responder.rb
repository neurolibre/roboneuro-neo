require_relative "../../lib/responder"
require_relative "../../lib/neurolibre_server_command"

module Neurolibre
class WeftConfirmResponder < Responder
  include NeurolibreServerCommand

  keyname :neurolibre_weft_confirm

  # What may follow the command on its line: the fields to confirm and the comment holding the corrections,
  # in either order.
  OPTIONS = /\A(?:fields[ \t]+(?<fields>.+?)(?:[ \t]+at[ \t]+(?<at>\d+))?|at[ \t]+(?<at2>\d+)(?:[ \t]+fields[ \t]+(?<fields2>.+))?)\z/i

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} weft confirm(?:[ \t]+([^\n]*?))?\.?[ \t\r]*$/i
  end

  def process_message(message)
    unless sent_by?(:author, :editor, :reviewer)
      respond("Only the paper's author, the issue's editor or a reviewer can ask for `@#{bot_name} weft confirm`.")
      return
    end
    rest = (match_data && match_data[1]).to_s.strip
    options = rest.empty? ? nil : OPTIONS.match(rest)
    if !rest.empty? && options.nil?
      respond("I could not read that. The command is `@#{bot_name} weft confirm`, `@#{bot_name} weft confirm " \
              "fields <names>` (names separated by commas) or either of them followed by `at <comment id>`.")
      return
    end
    fields = options && (options[:fields] || options[:fields2])
    at = options && (options[:at] || options[:at2])
    send_to_server(fields: fields && fields.strip, at: at && at.to_i)
  end

  def default_description
    "Confirm the description of the paper's data, all of it or the fields named, with the corrections in this " \
    "comment (or in the comment named with `at`) applied."
  end

  def default_example_invocation
    "@#{bot_name} weft confirm"
  end
end
end
