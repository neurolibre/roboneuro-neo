require_relative "../spec_helper.rb"

# NeuroLibre-specific characterization of ExternalServiceWorker's outbound
# request. These assertions are the contract with the NeuroLibre app
# (paper deposit, zenodo, binder, myst sync). Upstream has not touched this
# worker since the 2023 fork, but the payload fed into it is assembled by
# base-class code upstream does change, so the exact bytes are pinned here.
#
# Deliberately in its own file: upstream owns external_service_worker_spec.rb
# and editing it would add a 9th file to the shared conflict surface.
describe ExternalServiceWorker do

  let(:null_response) { OpenStruct.new(status: 700, body: "no reply") }
  let(:worker) { described_class.new }

  before { disable_github_calls_for(worker) }

  describe "NeuroLibre basic auth" do
    let(:service) do
      { 'name' => 'zenodo publish',
        'url' => 'https://preprint.neurolibre.org/api/zenodo/publish',
        'method' => 'post',
        'headers' => { 'username' => 'neuro', 'password' => 's3cret' } }
    end

    it "should collapse username and password into an Authorization header" do
      expected_headers = { 'Content-Type' => 'application/json',
                           'Accept' => 'application/json',
                           'Authorization' => "Basic " + Base64.strict_encode64("neuro:s3cret") }

      expect(Faraday).to receive(:post).with(service['url'], "{}", expected_headers).and_return(null_response)
      worker.perform(service, { 'bot_name' => 'botsci', 'issue_id' => 33 })
    end

    it "should not leak the raw username or password" do
      expect(Faraday).to receive(:post) do |_url, _body, headers|
        expect(headers).to_not have_key('username')
        expect(headers).to_not have_key('password')
        null_response
      end
      worker.perform(service, { 'bot_name' => 'botsci', 'issue_id' => 33 })
    end

    it "should leave headers alone when only one of username or password is set" do
      partial = service.merge('headers' => { 'username' => 'neuro' })
      expected_headers = { 'Content-Type' => 'application/json',
                           'Accept' => 'application/json',
                           'username' => 'neuro' }

      expect(Faraday).to receive(:post).with(service['url'], "{}", expected_headers).and_return(null_response)
      worker.perform(partial, { 'bot_name' => 'botsci', 'issue_id' => 33 })
    end
  end

  describe "the target-repository strip" do
    # SUSPECT: commented in the worker as a "required temporary solution for
    # python compatibility". It fires whenever an Authorization header is
    # present AND the request goes through the POST branch. It does NOT fire
    # for GET requests, even with the same Authorization header present -
    # see "NeuroLibre basic auth over GET" below.
    let(:service) do
      { 'name' => 'zenodo publish',
        'url' => 'https://preprint.neurolibre.org/api/zenodo/publish',
        'method' => 'post',
        'headers' => { 'username' => 'neuro', 'password' => 's3cret' },
        'data_from_issue' => ['target-repository'],
        'mapping' => { 'id' => 'issue_id', 'repository_url' => 'target-repository' } }
    end

    let(:locals) do
      { 'bot_name' => 'botsci',
        'issue_id' => 33,
        'repo' => 'neurolibre/reviews',
        'sender' => 'tester',
        'target-repository' => 'https://github.com/neurolibre/example' }
    end

    it "should send id and repository_url but drop target-repository" do
      expected_body = { 'id' => 33,
                        'repository_url' => 'https://github.com/neurolibre/example' }.to_json

      expect(Faraday).to receive(:post).with(service['url'], expected_body, hash_including('Authorization')).and_return(null_response)
      worker.perform(service, locals)
    end

    it "should keep target-repository when there is no auth header" do
      no_auth = service.reject { |k, _| k == 'headers' }
      expected_body = { 'target-repository' => 'https://github.com/neurolibre/example',
                        'id' => 33,
                        'repository_url' => 'https://github.com/neurolibre/example' }.to_json
      expected_headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

      expect(Faraday).to receive(:post).with(service['url'], expected_body, expected_headers).and_return(null_response)
      worker.perform(no_auth, locals)
    end

    it "should coerce a data_from_issue value that is absent from locals into an empty string, not a null" do
      # Pins the `.to_s` on the `inputs_from_issue` loop (external_service_worker.rb:29).
      # When the issue-extracted value isn't present in locals (nil), `.to_s`
      # turns it into "" before it ever reaches JSON -- without the `.to_s`,
      # the key would serialize as `null` instead. Both 'headers' (so the
      # strip branch is out of the way) and 'target-repository' are removed
      # from locals so this exercises the coercion in isolation.
      no_auth = service.reject { |k, _| k == 'headers' }
      locals_without_repo = locals.reject { |k, _| k == 'target-repository' }
      expected_body = { 'target-repository' => '',
                        'id' => 33,
                        'repository_url' => nil }.to_json
      expected_headers = { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }

      expect(Faraday).to receive(:post).with(service['url'], expected_body, expected_headers).and_return(null_response)
      worker.perform(no_auth, locals_without_repo)
    end
  end

  describe "send_only_mapped" do
    let(:service) do
      { 'name' => 'binder build',
        'url' => 'https://preprint.neurolibre.org/api/book/build',
        'method' => 'post',
        'headers' => { 'username' => 'neuro', 'password' => 's3cret' },
        'data_from_issue' => ['repo', 'sender'],
        'mapping' => { 'id' => 'issue_id', 'repository_url' => 'target-repository' },
        'send_only_mapped' => true }
    end

    let(:locals) do
      { 'bot_name' => 'botsci',
        'issue_id' => 33,
        'repo' => 'neurolibre/reviews',
        'sender' => 'tester',
        'target-repository' => 'https://github.com/neurolibre/example' }
    end

    it "should send only the mapped keys and ignore data_from_issue" do
      expected_body = { 'id' => 33,
                        'repository_url' => 'https://github.com/neurolibre/example' }.to_json

      expect(Faraday).to receive(:post).with(service['url'], expected_body, hash_including('Authorization')).and_return(null_response)
      worker.perform(service, locals)
    end

    it "should omit a mapped key that is absent from locals" do
      thin_locals = { 'bot_name' => 'botsci', 'issue_id' => 33 }
      expected_body = { 'id' => 33 }.to_json

      expect(Faraday).to receive(:post).with(service['url'], expected_body, hash_including('Authorization')).and_return(null_response)
      worker.perform(service, thin_locals)
    end

    # SUSPECT: settings-production.yml's myst-build commands combine
    # send_only_mapped with query_params (e.g. neurolibre_build_latest_preview_myst).
    # query_params are merged into the payload unconditionally, AFTER the
    # send_only_mapped branch runs - so "send only mapped" does not actually
    # restrict query_params, only the locals-derived keys.
    it "should still send query_params even though send_only_mapped is true" do
      with_query_params = service.merge(
        'query_params' => { 'commit_hash' => 'latest', 'is_prod' => false }
      )
      expected_body = { 'commit_hash' => 'latest',
                        'is_prod' => false,
                        'id' => 33,
                        'repository_url' => 'https://github.com/neurolibre/example' }.to_json

      expect(Faraday).to receive(:post).with(service['url'], expected_body, hash_including('Authorization')).and_return(null_response)
      worker.perform(with_query_params, locals)
    end
  end

  describe "NeuroLibre basic auth over GET" do
    # Real shape: neurolibre_preview_server_status / neurolibre_preprint_server_status
    # in settings-production.yml use method: get with username/password headers.
    # The Basic-auth collapse (lines 41-45) runs before the GET/POST branch, so
    # it applies here too - but the GET branch (line 47-48) never adds the
    # Content-Type/Accept headers and never runs the target-repository strip,
    # since that logic lives only in the POST branch.
    let(:service) do
      { 'name' => 'preprint server status',
        'url' => 'https://preprint.neurolibre.org/api/heartbeat',
        'method' => 'get',
        'headers' => { 'username' => 'neuro', 'password' => 's3cret' },
        'mapping' => { 'id' => 'issue_id' } }
    end

    it "should collapse auth headers and send bare mapped params as GET query params, with no Content-Type/Accept added" do
      expected_headers = { 'Authorization' => "Basic " + Base64.strict_encode64("neuro:s3cret") }
      expected_params = { 'id' => 33 }

      expect(Faraday).to_not receive(:post)
      expect(Faraday).to receive(:get).with(service['url'], expected_params, expected_headers).and_return(null_response)
      worker.perform(service, { 'bot_name' => 'botsci', 'issue_id' => 33 })
    end
  end

  describe "extra keys in locals" do
    # Upstream's merge adds issue_title to Responder#locals. This example
    # pins the fact that unmapped locals keys do NOT reach the wire, which
    # is what keeps that addition from changing the NeuroLibre payload.
    it "should not put unmapped locals keys into the request body" do
      service = { 'name' => 'zenodo status',
                  'url' => 'https://preprint.neurolibre.org/api/zenodo/status',
                  'method' => 'post',
                  'headers' => { 'username' => 'neuro', 'password' => 's3cret' },
                  'mapping' => { 'id' => 'issue_id' } }
      locals = { 'bot_name' => 'botsci',
                 'issue_id' => 33,
                 'issue_title' => '[REVIEW]: Something',
                 'repo' => 'neurolibre/reviews' }

      expect(Faraday).to receive(:post) do |_url, body, _headers|
        expect(JSON.parse(body)).to eq({ 'id' => 33 })
        null_response
      end
      worker.perform(service, locals)
    end
  end
end
