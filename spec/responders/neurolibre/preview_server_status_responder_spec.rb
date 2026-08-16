require_relative "../../spec_helper.rb"

describe Neurolibre::PreviewServerStatusResponder do

  subject { described_class }

  let(:settings) { { env: { bot_github_user: "botsci" } } }
  let(:params)   { { external_call: { url: "https://neurolibre.org" } } }
  let(:responder) { subject.new(settings, params) }

  describe "listening" do
    it "should listen to new comments" do
      expect(responder.event_action).to eq("issue_comment.created")
    end

    it "should match the invocation and its variants" do
      expect(responder.event_regex).to match("@botsci preview server status")
      expect(responder.event_regex).to match("@botsci preview server status.")
      expect(responder.event_regex).to match("@botsci preview server status   ")
    end

    it "should not match the preprint command" do
      expect(responder.event_regex).to_not match("@botsci preprint server status")
    end

    it "should be registered under its keyname" do
      expect(ResponderRegistry.available_responders["neurolibre_preview_server_status"]).to eq(described_class)
    end
  end

  describe "#process_message" do
    before do
      responder.context = OpenStruct.new(issue_id: 33,
                                         issue_author: "opener",
                                         issue_title: "[REVIEW]: Test",
                                         repo: "neurolibre/reviews",
                                         sender: "tester",
                                         issue_body: "<!--editor-->@arfon<!--end-editor-->" +
                                                     "<!--reviewers-list-->@xuanxu, @karthik<!--end-reviewers-list-->")
      disable_github_calls_for(responder)
    end

    it "should enqueue an ExternalServiceWorker" do
      expect { responder.process_message("") }.to change(ExternalServiceWorker.jobs, :size).by(1)
    end

    # Unlike the 15 Tier 1 responders, this one overrides locals to carry
    # editor and reviewer identity. If upstream changes user_login or
    # serializable, this example is what catches it.
    #
    # user_login (app/lib/github.rb) is pure string manipulation, not a live
    # GitHub call: `username.strip.sub(/^@/, "")`. disable_github_calls_for
    # does not need to stub it, and it does not, so this exercises the real
    # implementation end to end.
    it "should dispatch editor and reviewer identity alongside the base locals" do
      expected_params = { "url" => "https://neurolibre.org" }
      # issue_title arrived with the 2026-08 upstream merge (added to
      # Responder#locals). It reaches the worker but not the wire — see the
      # "extra keys in locals" example in
      # spec/workers/neurolibre_external_service_worker_spec.rb.
      expected_locals = { "bot_name" => "botsci",
                          "issue_author" => "opener",
                          "issue_id" => 33,
                          "issue_title" => "[REVIEW]: Test",
                          "repo" => "neurolibre/reviews",
                          "sender" => "tester",
                          "reviewers_usernames" => ["@xuanxu", "@karthik"],
                          "reviewers_logins" => "xuanxu,karthik",
                          "editor_username" => "@arfon",
                          "editor_login" => "arfon" }

      expect(ExternalServiceWorker).to receive(:perform_async).with(expected_params, expected_locals)
      responder.process_message("")
    end

    it "should refuse when there are no reviewers" do
      responder.context[:issue_body] = "<!--editor-->@arfon<!--end-editor-->"
      expect(responder).to receive(:respond).with("Can't perform this without reviewers")
      expect(responder).to_not receive(:process_external_service)
      responder.process_message("")
    end

    it "should refuse when there is no editor" do
      responder.context[:issue_body] = "<!--reviewers-list-->@xuanxu<!--end-reviewers-list-->"
      expect(responder).to receive(:respond).with("Can't perform this without an editor")
      expect(responder).to_not receive(:process_external_service)
      responder.process_message("")
    end
  end
end
