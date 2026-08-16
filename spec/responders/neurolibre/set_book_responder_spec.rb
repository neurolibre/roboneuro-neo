require_relative "../../spec_helper.rb"

describe Neurolibre::SetBookResponder do

  subject { described_class }

  let(:responder) { subject.new({ env: { bot_github_user: "botsci" } }, {}) }

  describe "listening" do
    it "should listen to new comments" do
      expect(responder.event_action).to eq("issue_comment.created")
    end

    it "should match the invocation and its variants" do
      expect(responder.event_regex).to match("@botsci set book uri")
      expect(responder.event_regex).to match("@botsci set book uri.")
      expect(responder.event_regex).to match("@botsci set book uri   ")
    end

    it "should not match a near miss" do
      expect(responder.event_regex).to_not match("@botsci set book uri now")
    end

    it "should be registered under its keyname" do
      expect(ResponderRegistry.available_responders["neurolibre_set_book"]).to eq(described_class)
    end
  end

  describe "#process_message" do
    # The URI is derived from the issue id, not from the message. Issue 33
    # zero-pads to 00033.
    let(:expected_uri) { "https://preprint.neurolibre.org/10.55458/neurolibre.00033" }

    before do
      disable_github_calls_for(responder)
      responder.context = OpenStruct.new(issue_id: 33,
                                         issue_author: "opener",
                                         repo: "neurolibre/reviews",
                                         sender: "tester",
                                         issue_body: "")
    end

    it "should derive a zero-padded URI from the issue id and confirm" do
      allow(Faraday).to receive(:head).with(expected_uri).and_return(double(status: 200))
      allow(Faraday).to receive(:head).with(expected_uri + ".pdf").and_return(double(status: 404))
      expect(responder).to receive(:update_value).with("book-exec-url", expected_uri).and_return(true)
      expect(responder).to receive(:respond).with("Done, set the URI for the reproducible preprint: [#{expected_uri}](#{expected_uri})")
      expect(responder).to receive(:respond).with(":page_with_curl: Looks like the summary PDF is not available on the NeuroLibre servers yet.")
      responder.process_message("")
    end

    it "should announce the summary PDF when it exists" do
      allow(Faraday).to receive(:head).with(expected_uri).and_return(double(status: 200))
      allow(Faraday).to receive(:head).with(expected_uri + ".pdf").and_return(double(status: 200))
      allow(responder).to receive(:update_value).and_return(true)
      expect(responder).to receive(:respond).with("Done, set the URI for the reproducible preprint: [#{expected_uri}](#{expected_uri})")
      expect(responder).to receive(:respond).with(":page_with_curl: [Summary PDF](#{expected_uri}.pdf) found online. Please check its validity before proceeding.")
      responder.process_message("")
    end

    it "should report when the value is not found in the body" do
      allow(Faraday).to receive(:head).and_return(double(status: 200))
      expect(responder).to receive(:update_value).with("book-exec-url", expected_uri).and_return(false)
      expect(responder).to receive(:respond).with("Error: book URI not found in the issue's body")
      expect(responder).to receive(:respond).with(/Summary PDF/)
      responder.process_message("")
    end

    it "should report a missing URI and respond only once" do
      allow(Faraday).to receive(:head).with(expected_uri).and_return(double(status: 404))
      expect(responder).to_not receive(:update_value)
      expect(responder).to receive(:respond).with("Looks like the URI #{expected_uri} does not exist.").once
      responder.process_message("")
    end
  end
end
