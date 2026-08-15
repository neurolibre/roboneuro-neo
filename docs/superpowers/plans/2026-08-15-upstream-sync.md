# Upstream Buffy Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a characterization test suite for the 20 NeuroLibre responders, then merge 132 upstream buffy commits behind it without silent behavior loss.

**Architecture:** Two phases in strict order. Phase 1 (Tasks 1–8) adds specs only, no production code, establishing a green baseline that will fail loudly if upstream changes base-class dispatch or the outbound request sent to the NeuroLibre app. Phase 2 (Tasks 9–12) adds `upstream` as a permanent remote, merges, and resolves five conflicts under a pre-agreed policy.

**Tech Stack:** Ruby 3.3.12, Sinatra 4.1.1, RSpec, Sidekiq (`sidekiq/testing`), WebMock, Rack::Test.

**Spec:** `docs/superpowers/specs/2026-08-15-upstream-sync-design.md`

## Global Constraints

- Ruby is pinned to **3.3.12** via `Gemfile`'s `ruby ENV.fetch("CUSTOM_RUBY_VERSION", "3.3.12")`. Local RVM may be 3.3.3 — run every command with `CUSTOM_RUBY_VERSION=3.3.3` prefixed, or bundler aborts with `Bundler::RubyVersionMismatch`.
- Full suite command: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color`
- Baseline before any work: **774 examples, 0 failures, 6 pending**. The 6 pending are COAR DB specs needing `DATABASE_URL`; leave them pending.
- All specs `require_relative` the spec helper by relative path. From `spec/responders/neurolibre/` that is `"../../spec_helper.rb"`.
- Bot name in all specs is `botsci`, matching existing suite convention.
- **Phase 1 changes no file under `app/`.** If a Phase 1 task appears to need a production change, stop and report instead.
- Characterization policy: assert what the code does **today**, even where it looks wrong. Mark suspect spots with a `# SUSPECT:` comment. Never fix inline.
- **The outbound contract with the NeuroLibre app is inviolable.** The exact URL, HTTP method, headers, and JSON body that `ExternalServiceWorker` sends must be byte-identical before and after the merge. Task 6 pins it; Task 7 proves the pin works. If the merge changes any of it, stop and report — do not adjust a spec to accommodate it.
- Never push, never merge a PR, never deploy. Branches and commits are local; the maintainer merges.

---

### Task 1: Tier 1 shared example group and table (15 responders)

**Files:**
- Create: `spec/responders/neurolibre/external_call_responders_spec.rb`

**Interfaces:**
- Consumes: `ResponderParams#sample_params`, `CommonActions#disable_github_calls_for` (already in `spec/support/`).
- Produces: nothing other tasks import. Self-contained file.

Context: these 15 responders are byte-identical apart from class name, keyname, regex, and two description strings. They do **not** override `locals`, so the payload is the base five keys from `Responder#locals` (`app/lib/responder.rb:179`).

- [ ] **Step 1: Write the failing test**

Create `spec/responders/neurolibre/external_call_responders_spec.rb`:

```ruby
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
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/external_call_responders_spec.rb --no-color`

Expected: failures. The likely first one is the keyname assertion — `ResponderRegistry.available_responders` may key on symbols rather than strings, and `locals` may include keys beyond the five listed.

- [ ] **Step 3: Correct the spec to match actual behavior**

This is a characterization suite: when a spec and the code disagree, **the spec is wrong**. Read the actual value and encode it.

To see the real registry keys:

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec ruby -e 'require "./app/buffy.rb"; puts ResponderRegistry.available_responders.keys.grep(/neurolibre/).inspect'
```

To see the real locals for one responder, add `puts responder.locals.inspect` temporarily inside the `before` block, run that one file, then remove it.

Adjust `expected_locals` and the keyname lookup to the observed values. Do not change anything under `app/`.

- [ ] **Step 4: Run until green**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/external_call_responders_spec.rb --no-color`

Expected: PASS, 90 examples (15 responders × 6 examples), 0 failures.

- [ ] **Step 5: Run the full suite**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color`

Expected: 864 examples, 0 failures, 6 pending.

- [ ] **Step 6: Commit**

```bash
git add spec/responders/neurolibre/external_call_responders_spec.rb
git commit -m "Characterize the 15 external-call NeuroLibre responders"
```

---

### Task 2: The `roles_and_issue?` guard paths

**Files:**
- Modify: `spec/responders/neurolibre/external_call_responders_spec.rb`

**Interfaces:**
- Consumes: `EXTERNAL_CALL_RESPONDERS` from Task 1.
- Produces: nothing.

Context: `roles_and_issue?` short-circuits `process_message` when the issue body lacks a reviewer or an editor (`app/responders/neurolibre/zenodo_status_responder.rb:19-31`). Real branching the Task 1 table does not reach.

- [ ] **Step 1: Write the failing test**

Add inside the `describe responder_class.name do` block, after the existing `#process_message` block:

```ruby
      describe "guard paths" do
        before do
          responder.context = OpenStruct.new(issue_id: 33,
                                             issue_author: "opener",
                                             issue_title: "[REVIEW]: Test",
                                             repo: "neurolibre/reviews",
                                             sender: "tester",
                                             issue_body: "")
          disable_github_calls_for(responder)
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

        it "should not enqueue a worker when refusing" do
          responder.context[:issue_body] = ""
          allow(responder).to receive(:respond)
          expect { responder.process_message("") }.to_not change(ExternalServiceWorker.jobs, :size)
        end
      end
```

- [ ] **Step 2: Run it**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/external_call_responders_spec.rb --no-color`

Expected: PASS, 135 examples. If a message string differs from the assertion, read the responder and encode the actual string — do not edit the responder.

- [ ] **Step 3: Run the full suite**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color`

Expected: 909 examples, 0 failures, 6 pending.

- [ ] **Step 4: Commit**

```bash
git add spec/responders/neurolibre/external_call_responders_spec.rb
git commit -m "Characterize the reviewer and editor guard paths"
```

---

### Task 3: `set_archive` and `set_book` responders

**Files:**
- Create: `spec/responders/neurolibre/set_archive_responder_spec.rb`
- Create: `spec/responders/neurolibre/set_book_responder_spec.rb`
- Read first: `app/responders/neurolibre/set_archive_responder.rb`, `app/responders/neurolibre/set_book_responder.rb`

**Interfaces:**
- Consumes: `CommonActions#disable_github_calls_for`.
- Produces: nothing.

Context: these two declare no `required_params :external_call`. They write into the issue body via `update_value` and reach the network through `Faraday.head`, rather than dispatching a worker.

`set_archive` (`app/responders/neurolibre/set_archive_responder.rb`) strips a `https://doi.org/` prefix from capture 1, accepts the literal `N/A` as a bypass, validates via `Faraday.head` accepting status 301 or 302, and writes to `"#{type}-archive"`.

`set_book` (`app/responders/neurolibre/set_book_responder.rb`) ignores its message entirely and *derives* the URI from the issue id as `https://preprint.neurolibre.org/10.55458/neurolibre.%05d`, then responds a **second** time about the summary PDF.

- [ ] **Step 1: Write `set_archive_responder_spec.rb`**

```ruby
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

    it "should accept the literal N/A without touching the network" do
      match!("@botsci set N/A as data archive")
      expect(Faraday).to_not receive(:head)
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
  end
end
```

- [ ] **Step 2: Write `set_book_responder_spec.rb`**

```ruby
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
```

- [ ] **Step 3: Run both files**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/set_archive_responder_spec.rb spec/responders/neurolibre/set_book_responder_spec.rb --no-color`

Expected: PASS, 19 examples (11 for `set_archive`, 8 for `set_book`).

These specs were written from a close read rather than from a run, so treat any failure as the spec being wrong about the code, not the code being wrong. Read the actual value and encode it. Two spots most likely to need adjusting: `update_value`'s exact arity, and whether `respond` is reached through `bg_respond` (already stubbed by `disable_github_calls_for`).

- [ ] **Step 4: Run the full suite and commit**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color   # expect 928 examples, 0 failures, 6 pending
git add spec/responders/neurolibre/set_archive_responder_spec.rb spec/responders/neurolibre/set_book_responder_spec.rb
git commit -m "Characterize the set_archive and set_book responders"
```

---

### Task 4: The two server-status responders

**Files:**
- Create: `spec/responders/neurolibre/preprint_server_status_responder_spec.rb`
- Create: `spec/responders/neurolibre/preview_server_status_responder_spec.rb`
- Read first: `app/responders/neurolibre/preprint_server_status_responder.rb`, `app/responders/neurolibre/preview_server_status_responder.rb`

**Interfaces:**
- Consumes: `CommonActions#disable_github_calls_for`.
- Produces: nothing.

Context: both are 68 lines rather than 60. The extra 8 lines are a `locals_with_editor_and_reviewers` override — **these two are the only NeuroLibre responders that actually send editor and reviewer identity to the external service**:

```ruby
  def locals_with_editor_and_reviewers
    locals.merge({ reviewers_usernames: reviewers_usernames,
                   reviewers_logins: reviewers_logins,
                   editor_username: editor_username,
                   editor_login: editor_login })
  end
```

That makes the dispatched payload here strictly richer than the Tier 1 five keys, and it is the single most valuable thing in this task to pin down — it exercises `user_login`, which lives in the upstream base class.

The two files are otherwise identical to each other apart from class name, keyname, regex, and descriptions.

- [ ] **Step 1: Write `preprint_server_status_responder_spec.rb`**

```ruby
require_relative "../../spec_helper.rb"

describe Neurolibre::PreprintServerStatusResponder do

  subject { described_class }

  let(:settings) { { env: { bot_github_user: "botsci" } } }
  let(:params)   { { external_call: { url: "https://neurolibre.org" } } }
  let(:responder) { subject.new(settings, params) }

  describe "listening" do
    it "should listen to new comments" do
      expect(responder.event_action).to eq("issue_comment.created")
    end

    it "should match the invocation and its variants" do
      expect(responder.event_regex).to match("@botsci preprint server status")
      expect(responder.event_regex).to match("@botsci preprint server status.")
      expect(responder.event_regex).to match("@botsci preprint server status   ")
    end

    it "should not match the preview command" do
      expect(responder.event_regex).to_not match("@botsci preview server status")
    end

    it "should be registered under its keyname" do
      expect(ResponderRegistry.available_responders["neurolibre_preprint_server_status"]).to eq(described_class)
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
    it "should dispatch editor and reviewer identity alongside the base locals" do
      expected_params = { "url" => "https://neurolibre.org" }
      expected_locals = { "bot_name" => "botsci",
                          "issue_author" => "opener",
                          "issue_id" => 33,
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
```

`user_login` resolves a `@username` to a GitHub login. `disable_github_calls_for` does not stub it, so if it makes a live call the spec will fail under WebMock. If that happens, stub it explicitly and record the real mapping:

```ruby
      allow(responder).to receive(:user_login) { |u| u.to_s.delete("@") }
```

- [ ] **Step 2: Write `preview_server_status_responder_spec.rb`**

Copy the Step 1 file and change exactly four things: the class to `Neurolibre::PreviewServerStatusResponder`, the command to `preview server status`, the keyname to `neurolibre_preview_server_status`, and the negative regex example to assert it does *not* match `@botsci preprint server status`. Everything else is identical — the two responders differ only in name, keyname, regex, and description strings.

- [ ] **Step 3: Run both files**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/preprint_server_status_responder_spec.rb spec/responders/neurolibre/preview_server_status_responder_spec.rb --no-color`

Expected: PASS, 16 examples (8 each).

- [ ] **Step 4: Run the full suite and commit**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color   # expect 944 examples, 0 failures, 6 pending
git add spec/responders/neurolibre/preprint_server_status_responder_spec.rb spec/responders/neurolibre/preview_server_status_responder_spec.rb
git commit -m "Characterize the preprint and preview server status responders"
```

---

### Task 5: The COAR responder

**Files:**
- Create: `spec/responders/neurolibre/coar_responder_spec.rb`
- Read first: `app/responders/neurolibre/coar_responder.rb` (200 lines)

**Interfaces:**
- Consumes: `CommonActions#disable_github_calls_for`.
- Produces: nothing.

Context: the outlier and the newest code. Keyname `neurolibre_coar`, no `required_params`. Its regex has two captures, one optional: `/\A@#{bot_name} coar\s+(\w+)(?:\s+from\s+(\w+))?\.?\s*$/i`.

Four subcommands (`app/responders/neurolibre/coar_responder.rb:61-76`): `request` (needs a service), `status`, `list`, `help`, plus an unknown-command fallback. Every path short-circuits first on `CoarNotify.enabled?`.

Note it is also the only NeuroLibre responder returning **arrays** from `default_description` and `default_example_invocation` — three entries each. `spec/responder_spec.rb` already asserts those two arrays are the same length, so that is covered; do not duplicate it.

Existing COAR specs live in `spec/coar_notify/` and cover models and routes, not this responder.

- [ ] **Step 1: Write the spec file**

```ruby
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
```

The `status` happy path with actual notification rows is deliberately omitted — it needs `DATABASE_URL`, and the 6 existing COAR specs are already pending for that reason. The empty-result path above covers the branch without a database.

- [ ] **Step 2: Run the file**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/responders/neurolibre/coar_responder_spec.rb --no-color`

Expected: PASS, 15 examples.

The stubs above guess at `CoarNotify::Models::ServiceRegistry`'s and `Notification`'s real interfaces. If a stub does not match, read the model in `app/coar_notify/models/` and correct the spec. Do not change the model.

- [ ] **Step 3: Run the full suite and commit**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color   # expect 959 examples, 0 failures, 6 pending
git add spec/responders/neurolibre/coar_responder_spec.rb
git commit -m "Characterize the COAR responder"
```

---

### Task 6: Pin the outbound wire contract to the NeuroLibre app

**Files:**
- Create: `spec/workers/neurolibre_external_service_worker_spec.rb`
- Read first: `app/workers/external_service_worker.rb`, `config/settings-production.yml`

**Interfaces:**
- Consumes: `CommonActions#disable_github_calls_for`.
- Produces: the assertions that guarantee the NeuroLibre API keeps receiving byte-identical requests across the merge.

Context — this is the task that protects paper deposit and every other NeuroLibre service call.

Tasks 1–5 stop at `ExternalServiceWorker.perform_async`. The actual HTTP request is built inside `ExternalServiceWorker#perform`, and **three of the steps that build it are NeuroLibre-only customizations with zero existing coverage**:

1. **Basic auth** (`app/workers/external_service_worker.rb:41-45`) — `username`/`password` headers are collapsed into a single `Authorization: Basic <base64>` header and the originals deleted. Every NeuroLibre service in `settings-production.yml` uses this.
2. **`send_only_mapped`** (`:23-26`) — when set, only `mapping` keys are sent, and only when present in locals. Used by roughly half the NeuroLibre services.
3. **The `target-repository` deletion** (`:54-56`) — when an `Authorization` header is present, `target-repository` is stripped from the payload, commented "required temporary solution for python compatibility."

`spec/workers/external_service_worker_spec.rb` (upstream's) covers none of the three — `grep -c` for any of them returns 0.

**Write this in a NEW file rather than extending upstream's spec.** Upstream's `external_service_worker_spec.rb` is currently *not* one of the 8 both-changed files; editing it would make it one and create a conflict every future sync. A separate file keeps the shared surface at 8.

- [ ] **Step 1: Write the wire-contract spec**

```ruby
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
    # present, which is every NeuroLibre service.
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
      expect(Faraday).to receive(:post) do |_url, body, _headers|
        expect(JSON.parse(body)).to have_key('target-repository')
        null_response
      end
      worker.perform(no_auth, locals)
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
```

- [ ] **Step 2: Run the file**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/workers/neurolibre_external_service_worker_spec.rb --no-color`

Expected: PASS, 9 examples.

Written from a close read, not from a run. If an expectation fails, the spec is wrong — read the actual request the worker builds and encode it. Note the worker calls `Logger.new(STDOUT).warn(parameters.to_json)` on every POST, so expect log noise in the output; that is current behavior, not a failure.

- [ ] **Step 3: Cross-check against the real production config**

The three services stubbed above are simplified. Confirm the shapes match reality:

```bash
grep -n "external_call" -A 20 config/settings-production.yml | grep -n "send_only_mapped\|mapping:\|data_from_issue" | head -30
```

If a real NeuroLibre service uses a shape none of the examples cover — a `query_params` block, a GET method, or a `mapping` onto a nested value — add an example for it. The goal is that every distinct *shape* in `settings-production.yml` has at least one pinned example.

- [ ] **Step 4: Run the full suite and commit**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color   # expect 968 examples, 0 failures, 6 pending
git add spec/workers/neurolibre_external_service_worker_spec.rb
git commit -m "Pin the outbound NeuroLibre service request contract"
```

---

### Task 7: Prove the tripwire actually trips

**Files:**
- Temporarily modify then revert: `app/lib/responder.rb:212-217`
- Temporarily modify then revert: `app/workers/external_service_worker.rb:41`

**Interfaces:**
- Consumes: every spec from Tasks 1–6.
- Produces: confidence that Phase 2 is verifiable. Nothing importable.

Context: a characterization suite that passes no matter what is worse than none, because it produces false confidence. This task verifies the suite fails when base-class dispatch breaks — which is precisely the failure mode the upstream merge could introduce.

**This is the one task that touches `app/`, and every change it makes is reverted before it finishes. It makes two breaks in sequence: one on the payload-assembly side, one on the wire side.**

- [ ] **Step 1: Record the green baseline**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color 2>&1 | tail -3`

Write the example count down. Confirm 0 failures.

- [ ] **Step 2: Break `process_external_service`**

In `app/lib/responder.rb`, change the body of `process_external_service` so it drops the locals:

```ruby
  def process_external_service(service_config, service_data)
    unless service_config.nil? || service_config.empty?
      service_locals = get_data_from_issue(service_config[:data_from_issue]).merge(service_data)
      ExternalServiceWorker.perform_async(serializable(service_config), {})   # TRIPWIRE TEST
    end
  end
```

- [ ] **Step 3: Confirm the suite goes red in the right place**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color 2>&1 | tail -20`

Expected: at least 15 failures, all in `external_call_responders_spec.rb`, all on the "should dispatch with the serialized config and locals" example.

If the suite stays green, the Tier 1 dispatch assertion is not doing its job. Fix the spec, then repeat from Step 2.

- [ ] **Step 4: Revert the first break**

```bash
git checkout app/lib/responder.rb
git diff --stat
```

Expected: empty diff.

- [ ] **Step 5: Break the wire contract**

The second tripwire, and the one that matters for the NeuroLibre app. In `app/workers/external_service_worker.rb`, disable the Basic auth collapse by changing line 41's condition:

```ruby
    if false && headers['username'] && headers['password']   # TRIPWIRE TEST
```

- [ ] **Step 6: Confirm the wire specs go red**

Run: `CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/workers/neurolibre_external_service_worker_spec.rb --no-color 2>&1 | tail -20`

Expected: at least 5 failures in `neurolibre_external_service_worker_spec.rb` — the auth examples, plus the `target-repository` strip examples, since that strip is conditioned on the `Authorization` header existing.

If those stay green, the wire contract is not actually pinned and Task 6 needs fixing before Phase 2 starts.

- [ ] **Step 7: Revert and confirm green**

```bash
git checkout app/workers/external_service_worker.rb
git diff --stat        # must be empty
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color 2>&1 | tail -3
```

Expected: empty diff, and the same count as Step 1 with 0 failures.

- [ ] **Step 8: Record both results**

Append to `docs/upstream-sync.md` (created in Task 12; if it does not exist yet, hold this note for that task):

> Both tripwires were verified before the 2026-08 merge:
> - Dropping locals in `Responder#process_external_service` turns 15 examples red.
> - Disabling the Basic auth collapse in `ExternalServiceWorker` turns the
>   NeuroLibre wire-contract examples red.

No commit — nothing changed on disk.

---

### Task 8: Suspect-behavior report

**Files:**
- Create: `docs/neurolibre-responder-notes.md`

**Interfaces:**
- Consumes: the `# SUSPECT:` comments left in Tasks 1–6.
- Produces: a decision list for the maintainer. No code depends on it.

Context: characterization policy says flag, never fix. This is where the flags are collected so they are a reviewable list rather than comments scattered across five files.

- [ ] **Step 1: Collect the flags**

```bash
grep -rn "SUSPECT:" spec/responders/neurolibre/
```

- [ ] **Step 2: Write the report**

Create `docs/neurolibre-responder-notes.md`. One section per suspect behavior with: what the code does, why it looks wrong, what would change if it were fixed, and a recommendation. Include at minimum the one already known:

> **`reviewers_logins`, `editor_login`, and `title_regex` are dead on 15 of 17 external-call responders.**
> All 17 define these methods. Only `preprint_server_status` and
> `preview_server_status` use them, via a `locals_with_editor_and_reviewers`
> override. The other 15 — including every zenodo command and
> `production_start` — pass the bare five-key `locals`, so the NeuroLibre API
> never receives editor or reviewer identity from them. `title_regex` is
> unreachable on all 17: no `process_message` calls it.
>
> The fact that two responders bothered to write the override is evidence the
> other 15 are an oversight rather than a decision. Fixing it changes what the
> API receives and needs coordination with the service side.
> Recommend: no change during the sync; revisit separately.

- [ ] **Step 3: Commit**

```bash
git add docs/neurolibre-responder-notes.md
git commit -m "Record suspect behaviors found while characterizing responders"
```

- [ ] **Step 4: STOP — Phase 1 gate**

Phase 1 is complete. Open a PR from this branch into `roboneuro/test` and hand it to the maintainer.

Do not begin Task 9 until the maintainer confirms Phase 1 is merged. Phase 2 rests on this baseline.

---

### Task 9: Add the upstream remote and take the merge

**Files:**
- Modify: `.git/config` (via `git remote add`)
- Resolve: `.ruby-version`, `Gemfile`, `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: a green Phase 1 baseline on `roboneuro/test`.
- Produces: a merge commit that advances the merge-base, so future syncs see only new commits.

Context: fork point is `5bbfaf2` (2023-04-30); upstream is 132 commits ahead. Trial merge showed 5 conflicting files. This task handles the 3 mechanical ones and defers the other 2.

- [ ] **Step 1: Branch and add the remote**

```bash
git checkout roboneuro/test
git pull
git checkout -b sync/upstream-2026-08
git remote add upstream https://github.com/openjournals/buffy.git
git fetch upstream
```

- [ ] **Step 2: Start the merge**

```bash
git merge upstream/main
```

Expected: conflicts in `.ruby-version`, `Gemfile`, `Gemfile.lock`, `.github/workflows/tests.yml`, `app/lib/doi_checker.rb`.

- [ ] **Step 3: Resolve `.ruby-version` — keep ours**

```bash
git checkout --ours .ruby-version
git add .ruby-version
cat .ruby-version   # must read 3.3.12
```

Upstream says `4.0.2`, but their CI matrix is `['3.3','3.4','4.0']`, so 3.3 remains supported. Heroku reads this file.

- [ ] **Step 4: Resolve `Gemfile` by hand**

Open it. The result must satisfy all three:
- the ruby line stays **ours**: `ruby ENV.fetch("CUSTOM_RUBY_VERSION", "3.3.12")`
- sinatra and sinatra-contrib take **theirs**: `4.2.1`
- `gem 'ostruct'` from upstream is **kept** (we solved the same deprecation with `require 'ostruct'` in `buffy_worker.rb`; both can coexist)

```bash
git add Gemfile
```

- [ ] **Step 5: Resolve `.github/workflows/tests.yml` — keep ours**

```bash
git checkout --ours .github/workflows/tests.yml
git add .github/workflows/tests.yml
```

Our matrix pins exact versions `['3.3.12', '3.4.10']` because the Gemfile declares a ruby version. Leave it. Adding 4.0 is deliberately out of scope for this merge.

- [ ] **Step 6: Do NOT commit yet**

`Gemfile.lock` and `app/lib/doi_checker.rb` remain conflicted. Tasks 10 and 11 handle them. Confirm:

```bash
git status --short | grep "^UU\|^AA"
```

Expected: exactly `Gemfile.lock` and `app/lib/doi_checker.rb`.

---

### Task 10: Integrate the `doi_checker.rb` conflict

**Files:**
- Resolve: `app/lib/doi_checker.rb`
- Test: `spec/doi_checker_spec.rb` (existing) — check whether upstream added cases

**Interfaces:**
- Consumes: the in-progress merge from Task 9.
- Produces: a `DOIChecker` carrying both upstream's structure and our Crossref resilience.

Context: **the only conflict requiring real thought.** Upstream restructured `check_dois` into `handle_special_case` / `handle_missing_doi` and added a `:skip` validity category. Our Crossref work — the polite-pool `Serrano.configuration`, the `MultiJson::ParseError` retry with backoff, and `CROSSREF_LOOKUP_DELAY` between lookups — was written inside the old structure. Neither side wins; ours gets re-applied onto theirs.

- [ ] **Step 1: See both sides in isolation**

```bash
git show :2:app/lib/doi_checker.rb > /tmp/ours.rb     # our version
git show :3:app/lib/doi_checker.rb > /tmp/theirs.rb   # upstream version
diff /tmp/ours.rb /tmp/theirs.rb
```

- [ ] **Step 2: Take upstream's structure wholesale**

```bash
cp /tmp/theirs.rb app/lib/doi_checker.rb
```

Start from their file so the new `:skip` category and `handle_special_case` chain arrive intact.

- [ ] **Step 3: Re-apply our three additions onto it**

1. The polite-pool config at the top, after the requires (needs `require 'multi_json'`):

```ruby
require 'multi_json'

# Join Crossref's "polite pool" (much higher, dedicated rate limit instead of
# the shared ~1 req/sec anonymous pool). Serrano also reads CROSSREF_EMAIL
# from the environment automatically, but we set a fallback here so bib files
# with many DOI-less entries don't trip the anonymous limit.
Serrano.configuration do |config|
  config.mailto = ENV['CROSSREF_EMAIL'] || 'noreply@neurolibre.org'
end
```

2. The three constants inside the class:

```ruby
  CROSSREF_MAX_ATTEMPTS = 3
  CROSSREF_RETRY_DELAY = 2 # seconds, doubled on each retry
  CROSSREF_LOOKUP_DELAY = 1 # seconds between sequential lookups in one paper
```

3. The retry wrapper, and `crossref_lookup` calling it:

```ruby
  def crossref_lookup(title)
    works = crossref_works_with_retry(title)
    return "CROSSREF-ERROR" if works.nil?
    # ...rest of upstream's crossref_lookup body unchanged...
  end

  # Serrano's own HTTP call (serrano/request_cursor.rb#_req) does a bare
  # `MultiJson.load(res.body)` with no status check and no retry, so a rate
  # limited (429, empty body) or otherwise non-JSON Crossref response raises
  # MultiJson::ParseError instead of a handleable Serrano error class. Retry
  # a few times with backoff before giving up, and log which title we were
  # querying so a failure is traceable instead of a bare stack trace.
  def crossref_works_with_retry(title)
    attempts = 0
    begin
      attempts += 1
      Serrano.works(query: title)
    rescue MultiJson::ParseError => e
      if attempts < CROSSREF_MAX_ATTEMPTS
        sleep(CROSSREF_RETRY_DELAY * attempts)
        retry
      else
        Logger.new(STDOUT).warn("DOIChecker: Crossref returned an unparseable response for title \"#{title}\" after #{attempts} attempts: #{e.message}")
        nil
      end
    end
  end
```

4. The inter-lookup sleep. In our old code this sat inside `check_dois`'s title branch; upstream moved that branch into `handle_missing_doi`. Put `sleep(CROSSREF_LOOKUP_DELAY)` at the **end of `handle_missing_doi`**, so it still throttles once per DOI-less entry.

- [ ] **Step 4: Run the DOI specs**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec spec/doi_checker_spec.rb --no-color
```

Expected: PASS, including any new upstream examples covering `:skip` and the ACM special case.

If a test hangs, the `sleep` calls are firing in tests. Stub them: `allow_any_instance_of(DOIChecker).to receive(:sleep)`. Add that to the spec, not to the production code.

- [ ] **Step 5: Stage it**

```bash
git add app/lib/doi_checker.rb
```

---

### Task 11: Regenerate the lockfile and land the merge

**Files:**
- Resolve: `Gemfile.lock`

**Interfaces:**
- Consumes: resolved `Gemfile` (Task 9) and `doi_checker.rb` (Task 10).
- Produces: the merge commit.

Context: the lockfile is generated, never hand-merged. Upstream's was produced by bundler 4.0.6 on Ruby 4; ours must be produced under our own pin.

- [ ] **Step 1: Regenerate rather than merge**

```bash
git checkout --ours Gemfile.lock
CUSTOM_RUBY_VERSION=3.3.3 bundle install
```

- [ ] **Step 2: Restore the Ruby pin in the lockfile**

`bundle install` under `CUSTOM_RUBY_VERSION=3.3.3` writes `3.3.3` into the lockfile's `RUBY VERSION` stanza, but Heroku must install 3.3.12. Commit `3d1ee61` did exactly this restore before; follow it.

```bash
grep -A2 "RUBY VERSION" Gemfile.lock
```

Edit that stanza to read `ruby 3.3.12p...` matching what was there before the merge:

```bash
git show HEAD:Gemfile.lock | grep -A2 "RUBY VERSION"
```

- [ ] **Step 3: Verify sinatra actually moved**

```bash
grep -E "^    sinatra " Gemfile.lock
```

Expected: `4.2.1`.

- [ ] **Step 4: Run the full suite**

```bash
CUSTOM_RUBY_VERSION=3.3.3 bundle exec rspec --no-color 2>&1 | tail -5
```

Expected: **the same example count as the end of Phase 1, 0 failures, 6 pending.**

A failure here is the entire point of the plan. Do not adjust a spec to make it pass — read what changed upstream, decide whether the new behavior is acceptable, and record the decision. If a NeuroLibre spec fails, that is a real regression the merge introduced; stop and report it rather than papering over it.

**A failure in `spec/workers/neurolibre_external_service_worker_spec.rb` is a hard stop.** That file is the contract with the NeuroLibre app. If it goes red, the merge changes what paper deposit and every other service receives, and the merge does not proceed until the cause is understood and the payload restored.

One known upstream change to check explicitly here: upstream adds `issue_title` to `Responder#locals` (`app/lib/responder.rb:184`). Analysis says it cannot reach the wire, because the request body is built only from `query_params`, `data_from_issue`, and `mapping` — never from locals wholesale. The "extra keys in locals" example in Task 6 is what proves that claim. Confirm it is green rather than assuming it.

- [ ] **Step 5: Commit the merge**

```bash
git add Gemfile.lock
git status --short   # no remaining UU entries
git commit
```

Write the merge message body to record each resolution:

```
Merge upstream buffy (132 commits since 5bbfaf2)

Resolutions:
- .ruby-version: ours (3.3.12). Upstream moved to 4.0.2 but still tests 3.3.
- Gemfile: ours for the ruby line, theirs for sinatra 4.2.1, kept their ostruct gem.
- .github/workflows/tests.yml: ours; our matrix pins exact patch versions.
- Gemfile.lock: regenerated under CUSTOM_RUBY_VERSION, ruby pin restored to 3.3.12.
- app/lib/doi_checker.rb: integrated. Took upstream's handle_special_case /
  handle_missing_doi restructure and the :skip category, re-applied our
  Crossref polite-pool config, MultiJson::ParseError retry, and per-lookup
  throttle onto it.
```

---

### Task 12: Sync documentation and the smoke checklist

**Files:**
- Create: `docs/upstream-sync.md`
- Create: `docs/upstream-sync-smoke-checklist.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the runbook for every future sync.

- [ ] **Step 1: Write `docs/upstream-sync.md`**

Include: the fork point and this sync's date; the remote and the branch-naming convention (`sync/upstream-YYYY-MM`); the full conflict-policy table from the design doc; the Task 6 tripwire result; and — critically — the *command* that regenerates the shared-file list rather than only the list itself, since it drifts as upstream moves:

````markdown
## Regenerating the shared-file risk surface

```bash
git fetch upstream
MB=$(git merge-base HEAD upstream/main)
comm -12 <(git diff --name-only $MB upstream/main | sort) \
         <(git diff --name-only $MB HEAD | sort)
```

As of the 2026-08 sync this listed 8 files. Those are the only files where
upstream and NeuroLibre both make changes, and therefore the entire conflict
surface.
````

Also record the sync procedure:

```bash
git fetch upstream
git checkout -b sync/upstream-YYYY-MM
git merge upstream/main
# resolve per the policy table, run the full suite, PR into roboneuro/test
```

- [ ] **Step 2: Write `docs/upstream-sync-smoke-checklist.md`**

A numbered list to run against a scratch preprint repo on the staging deploy, each item naming the command, the expected bot reply, and where to look if it fails (Heroku logs, Sidekiq dashboard):

1. `@roboneuro preview server status` — expect a status reply. **This is the
   single most informative check**: it is one of only two commands that sends
   editor and reviewer identity, so a success here exercises `user_login`,
   the Basic auth header, and the payload assembly all at once.
2. `@roboneuro preprint server status` — same, against the production server.
3. `@roboneuro production build runtime` — expect a build to start
4. `@roboneuro production sync myst` — expect a sync confirmation
5. `@roboneuro production sync data` — expect a sync confirmation
6. `@roboneuro zenodo status` — expect a status table
7. `@roboneuro zenodo create buckets` — the paper-deposit entry point; expect
   buckets to be created against a scratch record
8. `@roboneuro coar <subcommand>` — expect the COAR flow to respond
9. A GitHub Action responder command, if the review config uses one — confirms
   `trigger_workflow` still fires

For items 1–7, do not stop at "the bot replied." Confirm in the **Heroku logs**
that the request the NeuroLibre app received is the one it expected: the worker
logs the outgoing body on every POST (`Logger.new(STDOUT).warn(parameters.to_json)`
in `external_service_worker.rb`). A 200 with a silently different payload is the
exact failure this whole plan exists to catch, and the bot reply alone will not
show it. Compare a logged body against one captured from production *before* the
merge.

State explicitly at the top:

> `zenodo publish` and `zenodo flush` are **destructive** — `zenodo flush`'s own
> description reads "DESTRUCTIVE ACTION: Deletes zenodo records and all the data
> that has been uploaded." Run them only against throwaway Zenodo records, or
> skip them and rely on the characterization specs for those two commands.

- [ ] **Step 3: Commit**

```bash
git add docs/upstream-sync.md docs/upstream-sync-smoke-checklist.md
git commit -m "Document the upstream sync procedure and smoke checklist"
```

- [ ] **Step 4: STOP — Phase 2 gate**

Open a PR from `sync/upstream-2026-08` into `roboneuro/test`. The PR body carries the resolution table from the merge commit.

Do not merge it. Do not deploy. Hand to the maintainer, who merges, deploys to staging, and runs the smoke checklist. Fixes arising from the smoke pass go on a follow-up branch — never amended into the merge commit.
