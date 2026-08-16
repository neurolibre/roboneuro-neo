require_relative "../../spec_helper.rb"

describe Neurolibre::SetArchiveResponder do

  subject { described_class }

  let(:responder) { subject.new({ env: { bot_github_user: "botsci" } }, {}) }

  describe "listening" do
    it "should listen to new comments" do
      expect(responder.event_action).to eq("issue_comment.created")
    end

    it "should define regex with two captures" do
      match = responder.event_regex.match("@botsci set 10.5281/zenodo.6861996 as data archive")
      expect(match).to_not be_nil
      expect(match[1]).to eq("10.5281/zenodo.6861996")
      expect(match[2]).to eq("data")
    end

    it "should tolerate a trailing period" do
      expect(responder.event_regex).to match("@botsci set 10.5281/zenodo.6861996 as data archive.")
    end

    it "should not match without the archive keyword" do
      expect(responder.event_regex).to_not match("@botsci set 10.5281/zenodo.6861996 as data")
    end

    it "should be registered under its keyname" do
      expect(ResponderRegistry.available_responders["neurolibre_set_archive"]).to eq(described_class)
    end
  end

  describe "#process_message" do
    before do
      disable_github_calls_for(responder)
      responder.context = OpenStruct.new(issue_id: 33,
                                         issue_author: "opener",
                                         repo: "neurolibre/reviews",
                                         sender: "tester",
                                         issue_body: "")
    end

    def match!(msg)
      responder.match_data = responder.event_regex.match(msg)
    end

    it "should write the DOI and confirm on a valid archive" do
      match!("@botsci set 10.5281/zenodo.6861996 as data archive")
      expect(Faraday).to receive(:head).with("https://doi.org/10.5281/zenodo.6861996").and_return(double(status: 301))
      expect(responder).to receive(:update_value).with("data-archive", "10.5281/zenodo.6861996").and_return(true)
      expect(responder).to receive(:respond).with("Done, data archive is now [10.5281/zenodo.6861996](https://doi.org/10.5281/zenodo.6861996)")
      responder.process_message("")
    end

    it "should strip a doi.org prefix before storing" do
      match!("@botsci set https://doi.org/10.5281/zenodo.6861996 as book archive")
      expect(Faraday).to receive(:head).with("https://doi.org/10.5281/zenodo.6861996").and_return(double(status: 302))
      expect(responder).to receive(:update_value).with("book-archive", "10.5281/zenodo.6861996").and_return(true)
      expect(responder).to receive(:respond).with("Done, book archive is now [10.5281/zenodo.6861996](https://doi.org/10.5281/zenodo.6861996)")
      responder.process_message("")
    end

    # SUSPECT: the guard `valid_doi_value?(new_value) || new_value == "N/A"` still evaluates
    # valid_doi_value? first, so "N/A" is NOT a network-free bypass as the method's intent
    # ("accepts the literal N/A as a bypass") suggests. Faraday.head IS called with
    # https://doi.org/N/A, and "N/A" is only accepted afterwards because of the `|| new_value == "N/A"`
    # clause, regardless of what status (or error) that lookup returns.
    it "should accept the literal N/A even when the DOI lookup fails" do
      match!("@botsci set N/A as data archive")
      expect(Faraday).to receive(:head).with("https://doi.org/N/A").and_return(double(status: 404))
      expect(responder).to receive(:update_value).with("data-archive", "N/A").and_return(true)
      expect(responder).to receive(:respond).with("Done, data archive is now [N/A](https://doi.org/N/A)")
      responder.process_message("")
    end

    it "should report when the value is not found in the body" do
      match!("@botsci set 10.5281/zenodo.6861996 as nonexistent archive")
      expect(Faraday).to receive(:head).and_return(double(status: 301))
      expect(responder).to receive(:update_value).with("nonexistent-archive", "10.5281/zenodo.6861996").and_return(false)
      expect(responder).to receive(:respond).with("Error: `nonexistent` not found in the issue's body")
      responder.process_message("")
    end

    it "should reject an invalid DOI" do
      match!("@botsci set not-a-doi as data archive")
      expect(Faraday).to receive(:head).and_return(double(status: 404))
      expect(responder).to_not receive(:update_value)
      expect(responder).to receive(:respond).with("That doesn't look like a valid DOI value")
      responder.process_message("")
    end

    it "should treat a network error as an invalid DOI" do
      match!("@botsci set 10.5281/zenodo.6861996 as data archive")
      expect(Faraday).to receive(:head).and_raise(Faraday::ConnectionFailed.new("boom"))
      expect(responder).to receive(:respond).with("That doesn't look like a valid DOI value")
      responder.process_message("")
    end

    it "should reject a status 200 response as an invalid DOI" do
      match!("@botsci set 10.5281/zenodo.6861996 as data archive")
      expect(Faraday).to receive(:head).with("https://doi.org/10.5281/zenodo.6861996").and_return(double(status: 200))
      expect(responder).to_not receive(:update_value)
      expect(responder).to receive(:respond).with("That doesn't look like a valid DOI value")
      responder.process_message("")
    end
  end
end
