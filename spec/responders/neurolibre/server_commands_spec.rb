require_relative "../../spec_helper.rb"

# The commands that describe a paper's data (weft draft, check, confirm) and clean up the preview server after the
# technical screening. Each recognises its command, checks who wrote it, and sends the issue, the repository and
# the comment to the server, which does the rest and replies on the issue.

ISSUE_BODY = "<!--target-repository-->https://github.com/someone/seed-dispersal<!--end-target-repository-->" \
             "<!--editor-->@the-editor<!--end-editor-->" \
             "<!--reviewers-list-->@first-reviewer, @second-reviewer<!--end-reviewers-list-->"

def server_command(klass, url)
  responder = klass.new({ env: { bot_github_user: "roboneuro" } },
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

describe Neurolibre::WeftDraftResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/weft/draft") }

  it "recognises only its command" do
    expect(responder.event_regex).to match("@roboneuro weft draft")
    expect(responder.event_regex).to match("@roboneuro weft draft.")
    expect(responder.event_regex).not_to match("@roboneuro weft check")
    expect(responder.event_regex).not_to match("@roboneuro weft drafts")
  end

  it "sends the issue, the repository and the command's comment" do
    expect(payload(say(responder, "@roboneuro weft draft"))).to eq(
      "id" => 52, "repository_url" => "https://github.com/someone/seed-dispersal", "comment_id" => 555)
  end

  it "is for the editor and the reviewers" do
    expect(payload(say(responder, "@roboneuro weft draft", sender: "Second-Reviewer"))["id"]).to eq(52)
    expect(responder).to receive(:respond).with(/the issue's editor or a reviewer/)
    expect(say(responder, "@roboneuro weft draft", sender: "the-author")).to be_nil
  end
end

describe Neurolibre::WeftCheckResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/weft/check") }

  it "recognises the command with and without a comment to check" do
    expect(responder.event_regex).to match("@roboneuro weft check")
    expect(responder.event_regex).to match("@roboneuro weft check at 4242")
    expect(responder.event_regex).to match("@roboneuro weft check\n```yaml\nfields: []\n```")
    expect(responder.event_regex).not_to match("@roboneuro weft confirm")
  end

  it "passes the comment named with at" do
    expect(payload(say(responder, "@roboneuro weft check at 4242"))).to include("at" => 4242, "comment_id" => 555)
  end

  it "leaves out a comment that was not named" do
    expect(payload(say(responder, "@roboneuro weft check"))).not_to have_key("at")
  end

  it "is for the author, the editor and the reviewers" do
    expect(say(responder, "@roboneuro weft check", sender: "the-author")).not_to be_nil
    expect(responder).to receive(:respond).with(/the paper's author, the issue's editor or a reviewer/)
    expect(say(responder, "@roboneuro weft check", sender: "a-passer-by")).to be_nil
  end
end

describe Neurolibre::WeftConfirmResponder do
  let(:responder) { server_command(described_class, "https://preprint.example.org/api/weft/confirm") }

  it "recognises the command in its forms" do
    ["@roboneuro weft confirm", "@roboneuro weft confirm at 77", "@roboneuro weft confirm fields a, b",
     "@roboneuro weft confirm fields a, b at 77", "@roboneuro weft confirm\n```yaml\nx: 1\n```"].each do |c|
      expect(responder.event_regex).to match(c)
    end
    expect(responder.event_regex).not_to match("@roboneuro weft confirmed")
  end

  it "passes the fields and the comment named" do
    expect(payload(say(responder, "@roboneuro weft confirm fields depth, site at 77"))).to include(
      "fields" => "depth, site", "at" => 77, "comment_id" => 555)
    expect(payload(say(responder, "@roboneuro weft confirm at 77 fields depth"))).to include(
      "fields" => "depth", "at" => 77)
  end

  it "confirms everything when no fields are named" do
    expect(payload(say(responder, "@roboneuro weft confirm"))).not_to have_key("fields")
  end

  it "answers a line it cannot read with the forms it takes, and sends nothing" do
    expect(responder).to receive(:respond).with(/`@roboneuro weft confirm fields <names>`/)
    expect(say(responder, "@roboneuro weft confirm everything please")).to be_nil
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
