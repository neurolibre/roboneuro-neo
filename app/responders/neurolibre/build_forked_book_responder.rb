require_relative "../../lib/responder"

module Neurolibre
class BuildForkedBookResponder < Responder
# As this class is inherited from the responder, target_repo_value
# and branch_name_value are available (see responder.rb L298 and L306)
# See buffy_worker L40 to see why "locals" are needed for GitHub 
# interactions. Each GitHub event triggers a webhook, from which 
# context is inferred and locals are needed for auth etc.
  keyname :neurolibre_build_forked_book

  def define_listening
    required_params :data_from_issue
    @event_action = "issue_comment.created"
    @event_regex = /\A@#{bot_name} production build book\.?\s*$/i
  end

  def process_message(message)
    return unless roles_and_issue?
    # process_external_service(params[:external_call], locals_with_editor_and_reviewers)
    if target_repo_value.empty?
      respond("I couldn't find the URL for the target repository")
    else
      NeurolibreBookBuildWorker.perform_async(serializable(locals), target_repo_value, branch_name_value, context.issue_id, true)
    end

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

  def locals_with_editor_and_reviewers
    locals.merge({ reviewers_usernames: reviewers_usernames,
                   reviewers_logins: reviewers_logins,
                   editor_username: editor_username,
                   editor_login: editor_login })
  end

  def default_description
    "After screening, build book from the forked reository."
  end

  def default_example_invocation
    "@#{bot_name} production build book"
  end
end
end