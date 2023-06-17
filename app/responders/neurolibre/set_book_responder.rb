require_relative '../../lib/responder'
require 'uri'
require 'faraday'


module Neurolibre
  class SetBookResponder < Responder
    keyname :neurolibre_set_book

    def define_listening
      @event_action = "issue_comment.created"
      @event_regex = /\A@#{bot_name} set book uri\.?\s*$/i
    end

    def process_message(message)
      
      new_value = "https://preprint.neurolibre.org/10.55458/neurolibre.#{"%05d"%context.issue_id}"

      ok_reply = "Done, set the URI for the reproducible preprint: [#{new_value}](#{new_value})"
      nok_reply = "Error: book URI not found in the issue's body"
      response_pdf = nil
      if valid_url?(new_value)
        reply = update_value("book-exec-url", new_value) ? ok_reply : nok_reply
        if valid_url?(new_value + ".pdf")
          response_pdf = ":page_with_curl: [Summary PDF](#{new_value + ".pdf"}) found online. Please check its validity before proceeding."
        else
          response_pdf = ":page_with_curl: Looks like the summary PDF is not available on the NeuroLibre servers yet."
        end
      else
        reply = "Looks like the URI #{new_value} does not exist."
      end
      respond(reply)
      unless response_pdf.nil?
        respond(response_pdf)
      end
    end

    def valid_url?(archive_value)
      status_code = Faraday.head(archive_value).status
      return [200, 301, 302].include?(status_code)
    rescue
      return false
    end

    def default_description
      "Set executable book URI for the preprint."
    end

    def default_example_invocation
      "@#{bot_name} set book uri"
    end
  end
end