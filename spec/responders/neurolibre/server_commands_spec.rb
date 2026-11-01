require_relative "../../spec_helper.rb"

# The commands that describe a paper's data (crosswalk draft, check, confirm) and clean up the preview server after the
# technical screening. Each recognises its command, checks who wrote it, and sends the issue, the repository and
# the comment to the server, which does the rest and replies on the issue.

ISSUE_BODY = "<!--target-repository-->https://github.com/someone/seed-dispersal<!--end-target-repository-->" \
             "<!--editor-->@the-editor<!--end-editor-->" \
             "<!--reviewers-list-->@first-reviewer, @second-reviewer<!--end-reviewers-list-->"

def server_command(klass, url, teams: nil)
  responder = klass.new({ env: { bot_github_user: "roboneuro" }, teams: teams },
                        { external_call: { url: url, method: "post",
                                           data_from_issue: ["target-repository"],
                                           mapping: { id: "issue_id", repository_url: "target-repository" } } })
  disable_github_calls_for(responder)
  allow(responder).to receive(:issue_body).and_return(ISSUE_BODY)
  responder
end

def say(responder, comment, sender: "the-editor", comment_id: 555)
  responder.context = OpenStruct.new(issue_id: 52, issue_author: "the-author", repo: "neurolibre/reviews",
                                     sender: sender, comment_id: comment_id)
  responder.match_data = responder.event_regex.match(comment)
  sent = nil
  allow(ExternalServiceWorker).to receive(:perform_async) { |service, locals| sent = [service, locals] }
  responder.process_message(comment)
  sent
end

# What the server receives: the worker sends the issue's fields and each mapping entry, taken from the locals.
def payload(sent)
  service, locals = sent
  service["mapping"].to_h { |k, v| [k, locals[v]] }
end

describe Neurolibre::CrosswalkDraftResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/crosswalk/draft") }

  it "recognises only its command" do
    expect(responder.event_regex).to match("@roboneuro crosswalk draft")
    expect(responder.event_regex).to match("@roboneuro crosswalk draft.")
    expect(responder.event_regex).not_to match("@roboneuro crosswalk check")
    expect(responder.event_regex).not_to match("@roboneuro crosswalk drafts")
  end

  it "sends the issue, the repository and the command's comment" do
    expect(payload(say(responder, "@roboneuro crosswalk draft"))).to eq(
      "id" => 52, "repository_url" => "https://github.com/someone/seed-dispersal", "comment_id" => 555)
  end

  it "is for the editor and the reviewers" do
    expect(payload(say(responder, "@roboneuro crosswalk draft", sender: "Second-Reviewer"))["id"]).to eq(52)
    expect(responder).to receive(:respond).with(/NeuroLibre's editors and the issue's reviewers/)
    expect(say(responder, "@roboneuro crosswalk draft", sender: "the-author")).to be_nil
  end
end

describe Neurolibre::CrosswalkCheckResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/crosswalk/check") }

  it "recognises the command with and without a comment to check" do
    expect(responder.event_regex).to match("@roboneuro crosswalk check")
    expect(responder.event_regex).to match("@roboneuro crosswalk check at 4242")
    expect(responder.event_regex).to match("@roboneuro crosswalk check\n```yaml\nfields: []\n```")
    expect(responder.event_regex).not_to match("@roboneuro crosswalk confirm")
  end

  it "passes the comment named with at" do
    expect(payload(say(responder, "@roboneuro crosswalk check at 4242"))).to include("at" => 4242, "comment_id" => 555)
  end

  it "leaves out a comment that was not named" do
    expect(payload(say(responder, "@roboneuro crosswalk check"))).not_to have_key("at")
  end

  it "is for the author, the editor and the reviewers" do
    expect(say(responder, "@roboneuro crosswalk check", sender: "the-author")).not_to be_nil
    expect(responder).to receive(:respond).with(/the paper's author, NeuroLibre's editors and the issue's reviewers/)
    expect(say(responder, "@roboneuro crosswalk check", sender: "a-passer-by")).to be_nil
  end
end

describe Neurolibre::CrosswalkConfirmResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/crosswalk/confirm") }

  it "recognises the command in its forms" do
    ["@roboneuro crosswalk confirm", "@roboneuro crosswalk confirm at 77", "@roboneuro crosswalk confirm fields a, b",
     "@roboneuro crosswalk confirm fields a, b at 77", "@roboneuro crosswalk confirm\n```yaml\nx: 1\n```"].each do |c|
      expect(responder.event_regex).to match(c)
    end
    expect(responder.event_regex).not_to match("@roboneuro crosswalk confirmed")
  end

  it "passes the fields and the comment named" do
    expect(payload(say(responder, "@roboneuro crosswalk confirm fields depth, site at 77"))).to include(
      "fields" => "depth, site", "at" => 77, "comment_id" => 555)
    expect(payload(say(responder, "@roboneuro crosswalk confirm at 77 fields depth"))).to include(
      "fields" => "depth", "at" => 77)
  end

  it "confirms everything when no fields are named" do
    expect(payload(say(responder, "@roboneuro crosswalk confirm"))).not_to have_key("fields")
  end

  it "answers a line it cannot read with the forms it takes, and sends nothing" do
    expect(responder).to receive(:respond).with(/`@roboneuro crosswalk confirm fields <names>`/)
    expect(say(responder, "@roboneuro crosswalk confirm everything please")).to be_nil
  end
end

describe Neurolibre::PreviewCleanupResponder do
  let(:responder) { server_command(described_class, "https://preview.example.org/api/myst/cleanup") }

  it "recognises the command, with a build to keep" do
    expect(responder.event_regex).to match("@roboneuro preview cleanup")
    expect(responder.event_regex).to match("@roboneuro preview cleanup keep 2b3c4d5")
    expect(responder.event_regex).not_to match("@roboneuro preview cleanup everything")
  end

  it "passes the build to keep" do
    expect(payload(say(responder, "@roboneuro preview cleanup keep 2b3c4d5"))).to include("commit_hash" => "2b3c4d5")
    expect(payload(say(responder, "@roboneuro preview cleanup"))).not_to have_key("commit_hash")
  end
end

# NeuroLibre's editors run these commands on any paper, whether or not the issue names them; the editors team is in
# the settings as a list of logins or as a GitHub team, which GitHub is asked about.
describe "who may ask for the crosswalk commands" do
  it "lets a member of the editors team draft a paper the issue does not name them on" do
    responder = server_command(Neurolibre::CrosswalkDraftResponder, "https://preprint.example.org/api/crosswalk/draft",
                               teams: { editors: ["agah"] })
    expect(say(responder, "@roboneuro crosswalk draft", sender: "Agah")).not_to be_nil
  end

  it "asks GitHub when the editors team is given by its id" do
    responder = server_command(Neurolibre::CrosswalkCheckResponder, "https://preprint.example.org/api/crosswalk/check",
                               teams: { editors: 3408147 })
    github = double("github")
    allow(responder).to receive(:github_client).and_return(github)
    allow(github).to receive(:team_member?).with(3408147, "an-editor").and_return(true)
    allow(github).to receive(:team_member?).with(3408147, "a-passer-by").and_return(false)
    expect(say(responder, "@roboneuro crosswalk check", sender: "an-editor")).not_to be_nil
    expect(say(responder, "@roboneuro crosswalk check", sender: "a-passer-by")).to be_nil
  end

  it "refuses someone in no role and says who may ask" do
    responder = server_command(Neurolibre::CrosswalkDraftResponder, "https://preprint.example.org/api/crosswalk/draft",
                               teams: { editors: ["agah"] })
    expect(responder).to receive(:respond).with(/Only NeuroLibre.s editors and the issue.s reviewers/)
    expect(say(responder, "@roboneuro crosswalk draft", sender: "the-author")).to be_nil
  end
end
