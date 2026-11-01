# What the NeuroLibre commands that hand their work to a server share: who on the issue wrote the command, and
# the call itself. The server does the work and replies on the issue; the bot only recognises the command, checks
# who wrote it and sends the issue, the repository, the command's comment and the options the command gave.
module NeurolibreServerCommand
  # The person who wrote the command, by their role on the issue (:author, :editor, :reviewer) or in the journal
  # (:editors, a member of the editors team in the settings, whether or not this issue names them).
  def sent_by?(*roles)
    sender = context.sender.to_s.downcase
    logins = []
    logins << context.issue_author.to_s if roles.include?(:author)
    logins << issue_login("editor") if roles.include?(:editor)
    logins += read_value_from_body("reviewers-list").split(",").map { |r| user_login(r) } if roles.include?(:reviewer)
    return true if logins.compact.map(&:downcase).include?(sender)
    roles.include?(:editors) && editors_team_member?(sender)
  end

  # Whether a login is in the journal's editors team: the settings give the team as a list of logins or as a team
  # (its id or name), asked of GitHub. False when there is no such team or GitHub cannot say.
  def editors_team_member?(login)
    team = @teams && (@teams[:editors] || @teams["editors"])
    return false if team.nil? || login.empty?
    return team.map { |t| t.to_s.downcase }.include?(login) if team.is_a?(Array)
    team_id = team.is_a?(Integer) ? team : api_team_id(team)
    !team_id.nil? && github_client.team_member?(team_id, login)
  rescue StandardError
    false
  end

  # Send the command to the server: external_call's issue fields and mapping, plus the command's comment and the
  # options given. An option that is not given is left out, so the server sees it absent rather than empty.
  def send_to_server(options = {})
    service = Sinatra::IndifferentHash.new.merge(params[:external_call])
    mapping = Sinatra::IndifferentHash.new.merge(service[:mapping] || {})
    data = Sinatra::IndifferentHash.new
    { comment_id: context.comment_id }.merge(options).compact.each do |name, value|
      mapping[name] = "command_#{name}"
      data["command_#{name}"] = value
    end
    service[:mapping] = mapping
    process_external_service(service, locals.merge(data))
  end

  private

  def issue_login(field)
    value = read_value_from_body(field).to_s
    value.empty? ? nil : user_login(value)
  end
end
