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
        expect(responder).to receive(:respond).with(
          "❌ Please specify a service.\n\n**Usage:** `@botsci coar request from <service>`\n\n**Available services:** prereview, pci")
        expect(CoarNotify::Workers::SendWorker).to_not receive(:perform_async)
        responder.process_message("")
      end

      it "should reject an unknown service" do
        match!("@botsci coar request from nosuchservice")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:get).with("nosuchservice").and_return(nil)
        allow(CoarNotify::Models::ServiceRegistry).to receive(:service_names).and_return(["prereview"])
        expect(responder).to receive(:respond).with(
          "❌ Unknown service: **nosuchservice**\n\n**Available services:** prereview")
        expect(CoarNotify::Workers::SendWorker).to_not receive(:perform_async)
        responder.process_message("")
      end

      it "should enqueue a SendWorker for a known service" do
        match!("@botsci coar request from prereview")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:get).with("prereview").and_return({ "name" => "PREreview" })
        expect(responder).to receive(:respond).with(
          "🔄 Sending review request to **PREreview**...\n\n_This may take a few moments._")
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

      it "should render the status table, covering every status_icon branch and the service_name fallback" do
        match!("@botsci coar status")

        notifications = [
          double(direction: 'sent', status: 'processed', primary_type: 'ReviewRequest',
                 service_name: 'prereview', created_at: Time.utc(2024, 3, 1, 9, 5)),
          double(direction: 'received', status: 'failed', primary_type: 'RequestAccepted',
                 service_name: nil, created_at: Time.utc(2024, 3, 2, 14, 30)),
          double(direction: 'sent', status: 'processing', primary_type: 'ReviewRequest',
                 service_name: 'pci', created_at: Time.utc(2024, 3, 3, 8, 0)),
          double(direction: 'received', status: 'queued', primary_type: 'Acknowledgment',
                 service_name: 'prereview', created_at: Time.utc(2024, 3, 4, 23, 59))
        ]
        allow(CoarNotify::Models::Notification).to receive(:where).and_return(
          double(reverse_order: double(all: notifications)))

        expected = [
          "### COAR Notification Status",
          "",
          "| Direction | Type | Service | Status | Date |",
          "|-----------|------|---------|--------|------|",
          "| 📤 SENT | ReviewRequest | prereview | ✅ processed | 2024-03-01 09:05 |",
          "| 📥 RECEIVED | RequestAccepted | N/A | ❌ failed | 2024-03-02 14:30 |",
          "| 📤 SENT | ReviewRequest | pci | ⏳ processing | 2024-03-03 08:00 |",
          "| 📥 RECEIVED | Acknowledgment | prereview | ⏸️ queued | 2024-03-04 23:59 |",
          "",
          "_Total notifications: 4_"
        ].join("\n")

        expect(responder).to receive(:respond).with(expected)
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

      it "should list the configured services, including the supported_patterns line" do
        match!("@botsci coar list")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:all).and_return(
          { "prereview" => { "name" => "PREreview", "supported_patterns" => ["RequestReview"] } })

        expected = [
          "### Available COAR Services",
          "",
          "**prereview** - PREreview",
          "  - Supported patterns: RequestReview",
          "",
          "_To request a review:_ `@botsci coar request from <service>`"
        ].join("\n")

        expect(responder).to receive(:respond).with(expected)
        responder.process_message("")
      end

      it "should join multiple supported_patterns with a comma" do
        match!("@botsci coar list")
        allow(CoarNotify::Models::ServiceRegistry).to receive(:all).and_return(
          { "pci" => { "name" => "PCI", "supported_patterns" => ["RequestReview", "RequestEndorsement"] } })

        expected = [
          "### Available COAR Services",
          "",
          "**pci** - PCI",
          "  - Supported patterns: RequestReview, RequestEndorsement",
          "",
          "_To request a review:_ `@botsci coar request from <service>`"
        ].join("\n")

        expect(responder).to receive(:respond).with(expected)
        responder.process_message("")
      end
    end

    describe "help" do
      it "should print the help text" do
        match!("@botsci coar help")

        expected = <<~HELP
          ### COAR Notify Commands

          **Request review from a service:**
          ```
          @botsci coar request from <service>
          ```
          Sends a review request to an external service (e.g., PREreview, PCI).

          **Check notification status:**
          ```
          @botsci coar status
          ```
          Shows all COAR notifications for this issue.

          **List available services:**
          ```
          @botsci coar list
          ```
          Lists all configured COAR services.

          ---

          **About COAR Notify:**
          COAR Notify is a protocol for linking repository-based preprints with external review and endorsement services using standardized notifications.

          Learn more: https://coar-notify.net
        HELP

        expect(responder).to receive(:respond).with(expected)
        responder.process_message("")
      end
    end

    describe "an unknown subcommand" do
      it "should point at help" do
        match!("@botsci coar frobnicate")
        expect(responder).to receive(:respond).with(
          "❌ Unknown COAR command: `frobnicate`\n\nUse `@botsci coar help` for available commands.")
        responder.process_message("")
      end
    end
  end
end
