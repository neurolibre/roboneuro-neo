require_relative "../../spec_helper.rb"

describe Neurolibre::CoarResponder do

  subject { described_class }

  let(:responder) { subject.new({ env: { bot_github_user: "botsci" } }, {}) }

  describe "listening" do
    it "should listen to new comments" do
      expect(responder.event_action).to eq("issue_comment.created")
    end

    it "should capture a bare subcommand" do
      match = responder.event_regex.match("@botsci coar status")
      expect(match).to_not be_nil
      expect(match[1]).to eq("status")
      expect(match[2]).to be_nil
    end

    it "should capture the optional from clause" do
      match = responder.event_regex.match("@botsci coar request from prereview")
      expect(match).to_not be_nil
      expect(match[1]).to eq("request")
      expect(match[2]).to eq("prereview")
    end

    it "should not match a service name with a hyphen" do
      # SUSPECT: the captures are \w+, so a service key containing a hyphen
      # or dot is unreachable by this command.
      expect(responder.event_regex).to_not match("@botsci coar request from pci-registered")
    end

    it "should be registered under its keyname" do
      expect(ResponderRegistry.available_responders["neurolibre_coar"]).to eq(described_class)
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
      allow(CoarNotify).to receive(:enabled?).and_return(true)
    end

    def match!(msg)
      responder.match_data = responder.event_regex.match(msg)
    end

    describe "when COAR Notify is disabled" do
      it "should say so and do nothing else" do
        allow(CoarNotify).to receive(:enabled?).and_return(false)
        match!("@botsci coar status")
        expect(responder).to receive(:respond).with("ℹ️ COAR Notify is not enabled on this instance.")
        expect(CoarNotify::Workers::SendWorker).to_not receive(:perform_async)
        responder.process_message("")
      end
    end

    describe "request" do
      it "should ask for a service when none is given" do
        match!("@botsci coar request")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:service_names).and_return(["prereview", "pci"])
        expect(responder).to receive(:respond).with(/Please specify a service/)
        expect(CoarNotify::Workers::SendWorker).to_not receive(:perform_async)
        responder.process_message("")
      end

      it "should reject an unknown service" do
        match!("@botsci coar request from nosuchservice")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:get).with("nosuchservice").and_return(nil)
        allow(CoarNotify::Models::ServiceRegistry).to receive(:service_names).and_return(["prereview"])
        expect(responder).to receive(:respond).with(/Unknown service/)
        expect(CoarNotify::Workers::SendWorker).to_not receive(:perform_async)
        responder.process_message("")
      end

      it "should enqueue a SendWorker for a known service" do
        match!("@botsci coar request from prereview")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:get).with("prereview").and_return({ "name" => "PREreview" })
        expect(responder).to receive(:respond).with(/Sending review request to \*\*PREreview\*\*/)
        expect(CoarNotify::Workers::SendWorker).to receive(:perform_async).with(33, "prereview", "request_review")
        responder.process_message("")
      end

      it "should downcase the service name" do
        match!("@botsci coar request from PREreview")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:get).with("prereview").and_return({ "name" => "PREreview" })
        allow(responder).to receive(:respond)
        expect(CoarNotify::Workers::SendWorker).to receive(:perform_async).with(33, "prereview", "request_review")
        responder.process_message("")
      end
    end

    describe "status" do
      # CoarNotify::Models::Notification < Sequel::Model(:coar_notifications).
      # Merely resolving the constant (autoloaded) evaluates that superclass
      # expression, which raises Sequel::Error unless some Sequel connection
      # already exists as the model's default db -- independent of whatever
      # we stub afterwards. There is no real database in this suite (that is
      # why the 6 specs in spec/coar_notify/models/notification_spec.rb are
      # pending), and neither the pg nor sqlite3 adapter is installed, so we
      # can't connect for real. Sequel ships an in-process "mock" adapter for
      # exactly this: it satisfies Model's schema introspection without any
      # external driver or database, so the class can load and we can then
      # stub away every method we actually exercise below. We guard on
      # ENV['DATABASE_URL'] rather than Sequel::DATABASES.any? because the
      # latter only asks "does some connection already exist" -- true even
      # when another spec file grabbed the default DB slot for unrelated
      # reasons. What we actually need to know is "is a real database
      # configured for this suite", and ENV['DATABASE_URL'] is exactly the
      # signal spec/coar_notify/models/notification_spec.rb uses to decide
      # whether to pend its own specs. Keying on the same variable keeps the
      # two files in agreement regardless of run order: if DATABASE_URL is
      # set, we defer to the real connection notification_spec.rb expects;
      # otherwise we connect the mock here so this describe block's own
      # doubles have something legal to stub.
      before(:all) do
        Sequel.connect("mock://postgres") unless ENV['DATABASE_URL']
      end

      it "should report when there are no notifications" do
        match!("@botsci coar status")
        allow(CoarNotify::Models::Notification).to receive(:where).and_return(
          double(reverse_order: double(all: [])))
        expect(responder).to receive(:respond).with("ℹ️ No COAR notifications found for this issue.")
        responder.process_message("")
      end
    end

    describe "list" do
      it "should report when no services are configured" do
        match!("@botsci coar list")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:all).and_return({})
        expect(responder).to receive(:respond).with("ℹ️ No COAR services configured.")
        responder.process_message("")
      end

      it "should list the configured services" do
        match!("@botsci coar list")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:all).and_return(
          { "prereview" => { "name" => "PREreview", "supported_patterns" => ["RequestReview"] } })
        expect(responder).to receive(:respond).with(/\*\*prereview\*\* - PREreview/)
        responder.process_message("")
      end
    end

    describe "help" do
      it "should print the help text" do
        match!("@botsci coar help")
        expect(responder).to receive(:respond).with(/COAR Notify Commands/)
        responder.process_message("")
      end
    end

    describe "an unknown subcommand" do
      it "should point at help" do
        match!("@botsci coar frobnicate")
        expect(responder).to receive(:respond).with(/Unknown COAR command: `frobnicate`/)
        responder.process_message("")
      end
    end
  end
end
