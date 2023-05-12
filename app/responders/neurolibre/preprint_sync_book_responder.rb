require_relative "../../lib/responder"

module Neurolibre
class PreprintSyncBookResponder< Responder

  keyname :neurolibre_preprint_sync_book

  def define_listening
    required_params :external_call
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} production sync book\.?\s*$/i
  end

  def process_message(message)
    return unless roles_and_issue?
    NeurolibreBookBuildWorker.perform_async(serializable(locals), target_repo_value, branch_name_value)
    process_external_service(params[:external_call], locals)
  end

  def roles_and_issue?
    unless username?(reviewers_usernames.first.to_s)
      respond("Can't perform this without reviewers")
      return false
    end

    unless username?(editor_username)
      respond("Can't perform this without an editor")
      return false
    end

    true
  end

  def reviewers_usernames
    @reviewers_usernames ||= read_value_from_body("reviewers-list").split(",").map(&:strip)
  end

  def reviewers_logins
    @reviewers_logins ||= reviewers_usernames.map {|reviewer_username| user_login(reviewer_username)}.join(",")
  end

  def editor_username
    @editor_username ||= read_value_from_body("editor")
  end

  def editor_login
    @editor_login ||= user_login(editor_username)
  end

  def title_regex
    params[:review_title_regex] || /^\[REVIEW\]:/
  end

  def default_description
    "Transfer the final preprint (forked repo) to the preprint (production) server (DOI URL)."
  end

  def default_example_invocation
    "@#{bot_name} production sync book"
  end
end
end