require_relative "../../spec_helper.rb"

# Characterization specs for the 15 structurally identical NeuroLibre
# responders that dispatch to an external service. They differ only in
# keyname and command regex; everything asserted here is inherited
# behavior, which is exactly what an upstream merge can silently change.
describe "NeuroLibre external call responders" do

  EXTERNAL_CALL_RESPONDERS = {
    Neurolibre::BinderBuildResponder =>
      { keyname: :neurolibre_binder_build,           command: "production build runtime" },
    Neurolibre::BuildExtendedPdfResponder =>
      { keyname: :neurolibre_draft_extended_pdf,     command: "build extended pdf" },
    Neurolibre::CacheDataResponder =>
      { keyname: :neurolibre_cache_data,             command: "cache data" },
    Neurolibre::PreprintSyncDataResponder =>
      { keyname: :neurolibre_preprint_sync_data,     command: "production sync data" },
    Neurolibre::PreprintSyncPdfResponder =>
      { keyname: :neurolibre_sync_pdf,               command: "production sync pdf" },
    Neurolibre::ProductionStartResponder =>
      { keyname: :neurolibre_production_start,       command: "production start" },
    Neurolibre::SyncMystResponder =>
      { keyname: :neurolibre_sync_myst,              command: "production sync myst" },
    Neurolibre::ZenodoCreateBucketsResponder =>
      { keyname: :neurolibre_zenodo_create_buckets,  command: "zenodo create buckets" },
    Neurolibre::ZenodoFlushResponder =>
      { keyname: :neurolibre_zenodo_flush,           command: "zenodo flush" },
    Neurolibre::ZenodoPublishResponder =>
      { keyname: :neurolibre_zenodo_publish,         command: "zenodo publish" },
    Neurolibre::ZenodoStatusResponder =>
      { keyname: :neurolibre_zenodo_status,          command: "zenodo status" },
    Neurolibre::ZenodoUploadDataResponder =>
      { keyname: :neurolibre_zenodo_upload_data,     command: "zenodo upload data" },
    Neurolibre::ZenodoUploadDockerResponder =>
      { keyname: :neurolibre_zenodo_upload_docker,   command: "zenodo upload docker" },
    Neurolibre::ZenodoUploadMystResponder =>
      { keyname: :neurolibre_zenodo_upload_myst,     command: "zenodo upload myst" },
    Neurolibre::ZenodoUploadRepositoryResponder =>
      { keyname: :neurolibre_zenodo_upload_repository, command: "zenodo upload repository" }
  }.freeze

  EXTERNAL_CALL_RESPONDERS.each_pair do |responder_class, info|

    describe responder_class.name do

      let(:settings) { { env: { bot_github_user: "botsci" } } }
      let(:params)   { { external_call: { url: "https://neurolibre.org" } } }
      let(:responder) { responder_class.new(settings, params) }

      describe "listening" do
        it "should listen to new comments" do
          expect(responder.event_action).to eq("issue_comment.created")
        end

        it "should match the canonical invocation and its variants" do
          expect(responder.event_regex).to match("@botsci #{info[:command]}")
          expect(responder.event_regex).to match("@botsci #{info[:command]}.")
          expect(responder.event_regex).to match("@botsci #{info[:command]}   ")
        end

        it "should not match a near miss" do
          expect(responder.event_regex).to_not match("@botsci #{info[:command]} now")
          expect(responder.event_regex).to_not match("please @botsci #{info[:command]}")
        end

        it "should be registered under its keyname" do
          expect(ResponderRegistry.available_responders[info[:keyname].to_s]).to eq(responder_class)
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
                                                         "<!--reviewers-list-->@xuanxu<!--end-reviewers-list-->")
          disable_github_calls_for(responder)
        end

        it "should enqueue an ExternalServiceWorker" do
          expect { responder.process_message("") }.to change(ExternalServiceWorker.jobs, :size).by(1)
        end

        it "should dispatch with the serialized config and locals" do
          expected_params = { "url" => "https://neurolibre.org" }
          # These five keys come from Responder#locals. None of these
          # responders override it, so reviewers_logins / editor_login are
          # defined but never reach the worker.
          # SUSPECT: reviewers_logins, editor_login and title_regex are
          # defined on every one of these responders and used by none.
          expected_locals = { "bot_name" => "botsci",
                              "issue_author" => "opener",
                              "issue_id" => 33,
                              "repo" => "neurolibre/reviews",
                              "sender" => "tester" }

          expect(ExternalServiceWorker).to receive(:perform_async).with(expected_params, expected_locals)
          responder.process_message("")
        end
      end
    end
  end
end
