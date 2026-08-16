# NeuroLibre responder characterization notes

Written for the maintainer ahead of the 132-commit upstream merge. This is a
decision list, not a design doc. Everything below was produced by
characterization specs added in Phase 1 (`spec/responders/neurolibre/**`,
`spec/workers/neurolibre_external_service_worker_spec.rb`) that pin
NeuroLibre's existing behavior — zenodo, binder, preprint/preview sync,
production start, COAR, set_archive/set_book — before the merge lands. No
`app/` file was changed to produce this document; every claim below was
checked against the source and, where noted, against a deliberate break of
that source.

## A. The suite can be trusted to catch a regression

Three deliberate breaks were made in `app/lib/responder.rb` and
`app/workers/external_service_worker.rb`, the suite was run, and the break was
reverted each time (working tree confirmed pristine after each revert and at
the end, `git status --porcelain` empty). Baseline throughout: 970 examples,
0 failures, 6 pending.

1. **Payload assembly** (`Responder#process_external_service`): replaced the
   dispatched locals with `{}`. **21 examples went red**, not the 15 originally
   expected. 15 are the Tier-1 "dispatch with serialized config and locals"
   examples (one per external-call responder); 2 are the enriched-payload
   examples for the preprint/preview server-status responders. The remaining
   **4 are pre-existing upstream specs** (`spec/responder_spec.rb`,
   `external_start_review_responder_spec.rb`, `goodbye_responder_spec.rb`,
   `welcome_responder_spec.rb`) that independently assert on the locals
   payload passed to `ExternalServiceWorker.perform_async` and were not
   anticipated going in. **This means coverage of `process_external_service`
   is broader than the Phase 1 plan assumed** — a regression here will be
   caught by specs outside the NeuroLibre-specific suite too.
2. **Basic-auth collapse** (`ExternalServiceWorker`, the line that turns
   `username`/`password` headers into an `Authorization` header): disabled it.
   **7 of 10 examples** in `neurolibre_external_service_worker_spec.rb` went
   red.
3. **`target-repository` strip** (same file, the line that deletes
   `target-repository` from the outbound body when an `Authorization` header
   is present): disabled it. **Exactly 1 example** went red.

All three breaks were reverted; the suite returned to 970/0/6 each time. Full
detail in `.superpowers/sdd/2026-08-15-upstream-sync/task-7-report.md`.

**Takeaway:** if the merge silently changes what data reaches the NeuroLibre
API, or how auth headers are built, or how `target-repository` is handled,
these specs will fail. They are safe to treat as a merge gate for this part
of the codebase.

## B. Suspect behaviors found while characterizing

Each item: what the code does, why it looks wrong, what fixing it would
change, and a recommendation. None of these were fixed — characterization
policy is flag, never fix.

### B1. Editor/reviewer identity never reaches 15 of 17 external-call responders

All 17 NeuroLibre external-call responders (the 15 covered by
`external_call_responders_spec.rb` plus `preprint_server_status` and
`preview_server_status`) define `reviewers_logins`, `editor_login`, and
`title_regex`. Only `preprint_server_status` and `preview_server_status` use
them — they override `locals` via a `locals_with_editor_and_reviewers` helper
that adds `reviewers_logins`/`editor_login` to the base five keys. The other
15 — including every zenodo command and `production_start` — call
`process_external_service(params[:external_call], locals)` with the plain,
un-overridden `Responder#locals`, which returns exactly `bot_name`,
`issue_author`, `issue_id`, `repo`, `sender`. Verified directly:
`spec/responders/neurolibre/external_call_responders_spec.rb:99-108` pins the
five-key hash and is marked `# SUSPECT` in place.

**Why it looks wrong:** these 15 responder classes bother to define
`reviewers_logins`, `editor_login`, and memoize them — dead weight if never
meant to be sent. `title_regex` is unreachable on all 17 (nothing calls it
from `process_message`). The fact that exactly two responders wrote the
locals override that makes this data reach the wire is evidence the other 15
are a gap, not a deliberate design decision.

**What fixing it would change:** the NeuroLibre API would start receiving
`editor_login`/`reviewers_logins` on every zenodo/binder/sync/production
call, not just the two status checks. That is a wire-contract change and
needs sign-off from the service side before it's made.

**Recommendation:** no action during this merge. Revisit as a separate,
coordinated change if the maintainer wants editor/reviewer identity available
service-side for all 17 commands.

### B2. `set_archive`'s `N/A` bypass still makes the network call it's meant to skip

`SetArchiveResponder#process_message` guards on
`valid_doi_value?(new_value) || new_value == "N/A"`
(`app/responders/neurolibre/set_archive_responder.rb`). Ruby `||` evaluates
left-to-right, so `valid_doi_value?("N/A")` runs first, which calls
`Faraday.head("https://doi.org/N/A")` over the network — and only after that
call returns (or raises, which `valid_doi_value?` rescues to `false`) does the
`|| new_value == "N/A"` clause accept the value anyway. Pinned in
`spec/responders/neurolibre/set_archive_responder_spec.rb:60-70`
("should accept the literal N/A even when the DOI lookup fails"), which
explicitly expects `Faraday.head` to be called with `.../N/A` and stubs a 404
response, and the literal is accepted regardless.

**Why it looks wrong:** the `|| new_value == "N/A"` clause reads as a
network-free bypass for a special sentinel value, but it isn't one — it's
just a fallback accepted after a live HTTP call to `doi.org/N/A` (which will
always fail or 404, since `N/A` is not a real DOI). No functional bug today
(the outcome is still "accept N/A"), but it wastes a request per call. There
is no status code that flips this into a rejection — if `doi.org` ever
returned a 301/302 for `.../N/A`, `valid_doi_value?` would return `true` and
short-circuit the `||`, which still accepts `N/A`, the same outcome as today.
The one way the bypass genuinely fails to bypass is if `Faraday.head` raises
a non-`StandardError` exception: `valid_doi_value?`'s bare `rescue` only
catches `StandardError`, so such an exception would propagate out of
`process_message` before the `|| new_value == "N/A"` clause is ever reached.

**What fixing it would change:** reordering to
`new_value == "N/A" || valid_doi_value?(new_value)` would short-circuit and
skip the network call entirely for `N/A`, with no change in the response
sent to the user.

**Recommendation:** safe, low-risk fix, but out of scope for this
characterization-only merge. Flag for a follow-up cleanup PR.

### B3. COAR service names with a hyphen or dot are unreachable

`CoarResponder`'s command regex captures the service name with `\w+`, which
matches only word characters (letters, digits, underscore) — no hyphen, no
dot. `spec/responders/neurolibre/coar_responder_spec.rb:27-31` pins that
`@botsci coar request from pci-registered` does **not** match the command
regex at all, marked `# SUSPECT`.

**Why it looks wrong:** COAR/NDN service identifiers in the wild commonly use
hyphens (e.g. `pci-registered`) or dots. Any such service name is simply
unreachable through this command — the bot won't even recognize the
invocation as a COAR command, so the user gets whatever the "no responder
matched" fallback is, not a validation error naming the actual problem.

**What fixing it would change:** widening the capture (e.g. `[\w.-]+`) would
let hyphenated/dotted service names be recognized and passed through to
`CoarNotify`. Needs to be checked against whatever `CoarNotify` validates
service names against, so an out-of-scope value doesn't reach the notify
worker unfiltered.

**Recommendation:** no action during this merge; worth a follow-up once
NeuroLibre's actual COAR service catalog (and whether it includes
hyphenated/dotted names) is confirmed.

### B4. `send_only_mapped` does not restrict `query_params`

In `ExternalServiceWorker#perform` (`app/workers/external_service_worker.rb`),
`send_only_mapped: true` only changes how `mapped_parameters` is built from
`locals` via `mapping` — it has no effect on `query_params`, which are merged
into the outbound body unconditionally (`parameters =
query_parameters.merge(mapped_parameters)`). Pinned in
`spec/workers/neurolibre_external_service_worker_spec.rb` ("should still send
query_params even though send_only_mapped is true"), which is exactly why
that example was added in Task 6 beyond the brief's original 8 — real
production configs combine `send_only_mapped: true` with `query_params` in
five services in `config/settings-production.yml`:
`neurolibre_build_latest_preview_myst`, `neurolibre_build_latest_noexec_myst`,
`neurolibre_build_latest_noexec_nocache_myst`,
`neurolibre_build_production_noexec_myst`, and
`neurolibre_build_production_myst`.

**Why it looks wrong:** the flag name reads as "send only the mapped data,"
i.e. a total restriction on the outbound payload. It's actually a partial
restriction — it only prunes the `data_from_issue`/`mapping`-derived keys,
not `query_params`. Anyone reasoning about the name alone would misjudge what
data a `send_only_mapped` service actually transmits.

**What fixing it would change:** making `send_only_mapped` also gate
`query_params` would strip `commit_hash`/`is_prod` (and similar) from the
five myst-build services above, which currently rely on those values
reaching the API. That would break those services today.

**Recommendation:** no action — this is working as currently relied upon.
Rename or document the flag if it's ever revisited; do not change its
behavior.

### B5. `target-repository` strip only runs in the POST branch (latent trap, not a bug today)

`ExternalServiceWorker#perform` deletes `target-repository` from the outbound
body only inside the POST branch's `if headers['Authorization']` check —
textually inside the `else` of `if http_method.downcase == 'get'`. A GET
request with the identical `Authorization` header never runs this strip at
all, because that code path doesn't exist on the GET side. Pinned in
`spec/workers/neurolibre_external_service_worker_spec.rb`, "NeuroLibre basic
auth over GET" (no strip logic runs for GET) versus "the target-repository
strip" (POST-only).

**State clearly: this has zero production impact today.** Neither GET
service in `config/settings-production.yml` (`neurolibre_preview_server_status`,
`neurolibre_preprint_server_status`) sends `target-repository` — their
`mapping` is `id: issue_id` only, and neither has a `data_from_issue` entry.
There is no live GET request today that could leak `target-repository` onto
the wire.

**Why it's worth flagging anyway:** it's a latent trap. If a future GET-based
service is added with `data_from_issue: [target-repository]`, the strip
silently would not apply, and `target-repository` would leak into that
request's query parameters even with `Authorization` present — the opposite
of what the POST case does.

**Recommendation: do NOT "fix" this during the merge.** The two current GET
services don't exercise this path, so changing it now only adds risk for no
behavioral gain. Note it as a design gap to close if and when a GET service
that uses `data_from_issue` is ever added.

## C. What the wire actually carries for ~13 zenodo/binder/sync/production calls

The single most load-bearing fact from this characterization work: of the 15
NeuroLibre auth POST services that are **not** `send_only_mapped`, 13 carry
`data_from_issue: [target-repository]` and nothing else, and for those 13 the
resulting request body is just `{"id":N,"repository_url":U}` —
`data_from_issue` contributes nothing extra to the wire. The remaining 2
(`neurolibre_zenodo_status`, `neurolibre_sync_pdf`) have no `data_from_issue`
at all and send only `{"id":N}`. 13 + 2 = 15 accounts for every
non-`send_only_mapped` auth POST service.

Verified directly against `config/settings-production.yml` and
`app/workers/external_service_worker.rb`:

- 13 non-`send_only_mapped` services carry `data_from_issue: [target-repository]`:
  `neurolibre_preprint_sync_data`, `neurolibre_production_start`,
  `neurolibre_zenodo_create_buckets`, `neurolibre_zenodo_upload_repository`,
  `neurolibre_zenodo_upload_docker`, `neurolibre_zenodo_upload_data`,
  `neurolibre_zenodo_flush`, `neurolibre_zenodo_publish`,
  `neurolibre_draft_extended_pdf`, `neurolibre_binder_build`,
  `neurolibre_sync_myst`, `neurolibre_cache_data`,
  `neurolibre_zenodo_upload_myst`. Each pairs it with
  `mapping: { id: issue_id, repository_url: target-repository }`.
- `Responder#process_external_service` (`app/lib/responder.rb:212-217`)
  merges `get_data_from_issue(service_config[:data_from_issue])` (reads
  `target-repository` from the issue body) into the base locals before
  dispatching to `ExternalServiceWorker.perform_async`. So the worker
  receives a `target-repository` key alongside the base five.
- In `ExternalServiceWorker#perform`'s non-`send_only_mapped` branch, the
  `inputs_from_issue` loop copies `target-repository` into
  `mapped_parameters['target-repository']`, and separately the `mapping` loop
  sets `mapped_parameters['repository_url'] = locals.delete('target-repository')`
  and `mapped_parameters['id'] = locals.delete('issue_id')`. Both the
  duplicate `target-repository` entry and `repository_url` now sit in
  `parameters`. The POST branch's `if headers['Authorization']` then deletes
  `target-repository` (see B5) — leaving exactly `{"id":N,"repository_url":U}`.

This matches `spec/workers/neurolibre_external_service_worker_spec.rb`'s "the
target-repository strip" example precisely (`{'id'=>33,
'repository_url'=>'https://github.com/neurolibre/example'}.to_json`, with
`target-repository` absent from the body).

**Implication for the merge:** if upstream's merge touches
`Responder#process_external_service`, `Responder#get_data_from_issue`, or
`ExternalServiceWorker#perform`, the specs in section A will catch it. If the
maintainer is auditing what data NeuroLibre's zenodo/binder/production calls
actually send today, this is it: an issue ID and a repository URL, nothing
else, regardless of what `data_from_issue` or the responder's `locals`
override would suggest.

## D. One CI caveat: `DATABASE_URL` and `CoarNotify.enabled?` must move together

`spec/responders/neurolibre/coar_responder_spec.rb`'s `"status"` describe
block connects Sequel's in-process mock adapter
(`Sequel.connect("mock://postgres")`) **unless `ENV['DATABASE_URL']` is set**
(`coar_responder_spec.rb:122-124`). This is deliberate: the spec needs
`CoarNotify::Models::Notification` to be a loadable class (merely resolving
the constant evaluates `Sequel::Model(:coar_notifications)`, which raises
`Sequel::Error` without some Sequel connection present as the model's default
db), and when no real database is configured, the mock adapter satisfies that
requirement without a real driver.

The gap: `CoarNotify.init!` (`app/coar_notify/coar_notify.rb:145-146`) only
establishes a real database connection `unless enabled?` returns false — i.e.
if `CoarNotify.enabled?` is false, no connection is made at boot **even if
`DATABASE_URL` is set**. In that specific configuration (`DATABASE_URL` set,
`CoarNotify.enabled?` false), nothing connects anything: the app skips it
because it's disabled, and `coar_responder_spec.rb` skips its own mock
connect because `DATABASE_URL` is set. The COAR status specs will raise
`Sequel::Error` rather than run.

This was a deliberate choice in the characterization work, not an oversight:
the alternative (guarding on "is any Sequel connection already open," e.g.
`Sequel::DATABASES.any?`) risked silently binding the real
`CoarNotify::Models::Notification` model to a mock adapter left open by an
unrelated spec file and passing while testing nothing.

**This is not a new failure mode.** `spec/coar_notify/models/notification_spec.rb`
already skips its 6 examples only when `ENV['DATABASE_URL']` is unset
(`skip 'Database tests - run with DATABASE_URL set' unless ENV['DATABASE_URL']`,
`notification_spec.rb:14`) — it has no `CoarNotify.enabled?` check either, so
it is already broken in the same `DATABASE_URL`-set-but-disabled
configuration, for the same underlying reason (no real connection actually
gets established).

**Recommendation:** in whatever CI configuration runs this suite, set
`DATABASE_URL` and enable COAR Notify together, or leave both unset/disabled
together. Don't set `DATABASE_URL` alone expecting COAR to be exercised —
check `CoarNotify.enabled?` in that same environment first.
