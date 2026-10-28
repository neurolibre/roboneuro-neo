require_relative "../../lib/responder"
require_relative "../../lib/neurolibre_server_command"

module Neurolibre
class PreviewCleanupResponder < Responder
  include NeurolibreServerCommand

  keyname :neurolibre_preview_cleanup

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} preview cleanup(?:[ \t]+keep[ \t]+([0-9a-f]{7,40}))?\.?[ \t\r]*$/i
  end

  def process_message(message)
    send_to_server(commit_hash: match_data && match_data[1])
  end

  def default_description
    "After the technical screening: keep the author's last build on the preview server (and the build of the " \
    "commit given with `keep`), remove the other builds and the images pulled for the repository."
  end

  def default_example_invocation
    "@#{bot_name} preview cleanup"
  end
end
end
