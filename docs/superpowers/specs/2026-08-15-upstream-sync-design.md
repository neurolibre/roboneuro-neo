# Keeping up with upstream buffy without damaging NeuroLibre functionality

Design doc — 2026-08-15

## Problem

This repo is a fork of `openjournals/buffy` that diverged at `5bbfaf2`
(2023-04-30). Upstream has moved 132 commits since; the fork has moved 309.
Nobody has synced in over three years.

Two separate problems hide behind "can we catch up":

1. **The merge itself.** Small. Measured, not estimated (see below).
2. **The absence of a regression detector for NeuroLibre code.** Large, and
   the reason the merge is currently unsafe.

## Measurements

Taken 2026-08-15 against `upstream/main` at `c10bf36`.

| Fact | Value |
|---|---|
| Fork point | `5bbfaf2`, 2023-04-30 |
| Upstream commits since fork | 132 |
| Our commits since fork | 309 |
| Our diff vs fork point | +16,502 / −115 across 97 files |
| Upstream files we deleted | 0 |
| Files changed by **both** sides | 8 |
| Conflicting files in a trial merge | 5 |
| Current suite | 774 examples, 0 failures, 6 pending |

The fork is almost purely additive. That is why a merge is viable at all.

Trial merge performed non-destructively with
`git merge-tree --write-tree HEAD upstream/main`. Conflicts:
`.ruby-version`, `Gemfile`, `Gemfile.lock`, `.github/workflows/tests.yml`,
`app/lib/doi_checker.rb`. Everything else auto-merges.

### The eight shared files

These are the entire risk surface for every future sync:

```
.github/workflows/tests.yml     .ruby-version
app/lib/doi_checker.rb          app/workers/buffy_worker.rb
Gemfile                         Gemfile.lock
README.md                       spec/responders/goodbye_responder_spec.rb
```

### The real risk

`app/responders/neurolibre/` holds 20 responders. `spec/responders/neurolibre/`
does not exist.

Existing generic coverage in `spec/responder_spec.rb` iterates
`ResponderRegistry.available_responders` and asserts only that each responder
instantiates and has a non-empty `default_description` and
`default_example_invocation`. It never checks a regex, a keyname, or what
`process_message` dispatches.

Upstream's 132 commits touch `app/lib/responder.rb`,
`app/workers/buffy_worker.rb`, `app/lib/utilities.rb`, and `app/lib/github.rb`
— base classes all 20 NeuroLibre responders inherit from. (Not
`external_service_worker.rb`; see the outbound-contract audit below.) Git
merges those cleanly and silently. Nothing in the suite would report a
behavioral shift underneath the NeuroLibre surface.

The safety net therefore comes first, and the merge second.

### The outbound contract with the NeuroLibre app

Everything NeuroLibre does beyond posting comments — paper deposit, zenodo,
binder builds, myst sync, preprint sync — leaves through
`ExternalServiceWorker#perform`. That contract must survive the merge intact.
Audited 2026-08-15:

**Structurally well insulated.** Upstream has made **zero** changes to
`app/workers/external_service_worker.rb` since the fork. All three NeuroLibre
customizations in it are untouched by upstream:

- Basic auth: `username`/`password` headers collapsed into
  `Authorization: Basic <base64>` (`:41-45`)
- `send_only_mapped`: send only `mapping` keys, and only when present (`:23-26`)
- the `target-repository` strip when an `Authorization` header is present,
  commented "required temporary solution for python compatibility" (`:54-56`)

`config/settings-production.yml`, which defines every NeuroLibre service call,
is likewise untouched by upstream. `app/lib/github.rb` — the GitHub Actions
path — changed by exactly one *additive* method (`react_to_comment`);
`trigger_workflow` is untouched.

**But untested.** `spec/workers/external_service_worker_spec.rb` is upstream's
and covers none of the three customizations. The wire format is therefore
protected by nothing but the fact that upstream has not yet touched that file.

**One upstream change reaches the payload assembly.** Upstream adds
`issue_title` to `Responder#locals` (`app/lib/responder.rb:184`). It cannot
reach the wire — the request body is built only from `query_params`,
`data_from_issue`, and `mapping`, never from locals wholesale — but that is an
argument, not a test, and the plan pins it with one.

The plan therefore adds a dedicated task pinning the exact URL, method,
headers, and JSON body for each service *shape* in `settings-production.yml`,
in a **new spec file** rather than extending upstream's — editing upstream's
would grow the shared conflict surface from 8 files to 9.

### Upstream changes that do alter NeuroLibre-visible behavior

Two, both in upstream-owned code we never modified, so both merge cleanly and
land silently:

1. **`run_gitinspector` is deleted** from `utilities.rb`, along with its caller
   in `repo_checks_worker.rb` and its specs. The software report posted by repo
   checks loses its gitinspector section. Consistent and intentional upstream;
   a visible change to bot output, not to the NeuroLibre API.
2. **`clone_repo` and `change_branch` are hardened** — argv-form `Open3` calls
   instead of shell interpolation, `clone_repo` now requires an http/https
   scheme, and `change_branch` rejects any branch not matching
   `/\A(?!-)[\w.\-\/]+\z/`. These are command-injection fixes. They affect
   `BuffyWorker#prepare_local_repo`, used by repo checks. NeuroLibre's own
   worker (`NeurolibreBookBuildTestWorker`) does not clone at all — it POSTs to
   the NeuroLibre API — so the deposit path is unaffected. A review branch with
   an unusual name would now be rejected where it previously worked.

## Non-goals

- Rebasing the fork onto upstream. 309 commits across 97 files, and it rewrites
  history the deploy branches point at.
- Vendoring buffy as a gem or submodule. Upstream is not packaged for it.
- A scheduled CI drift check. Deferred; the permanent remote plus
  `docs/upstream-sync.md` is the agreed mechanism.
- Testing the NeuroLibre API endpoints themselves. Specs assert the correct
  outbound call is dispatched, not what the service does with it.
- Making the 6 `DATABASE_URL`-pending COAR specs run. Separate work.

## Phases

Each phase is one PR into `roboneuro/test`. `roboneuro/test` is currently at
the same commit as `main` (0 ahead, 0 behind), so it is a true staging
rehearsal rather than a divergent branch.

Merging any PR, and any promotion to `main` or production, is the maintainer's
action, not the implementer's.

### Phase 1 — `spec/neurolibre-characterization`

Characterization specs for the 20 NeuroLibre responders, plus the outbound
wire contract in `ExternalServiceWorker`. **No production code changes.** Lands green on top of today's `main` so the baseline exists before
anything upstream moves.

Independently valuable: if the merge is deferred, the tests still stand.

### Phase 2 — `sync/upstream-2026-08`

Add `upstream` as a permanent remote. `git merge upstream/main`. Resolve the 5
conflicts. Suite stays green. One merge commit, so the merge-base advances and
the next sync sees only new commits.

Also lands `docs/upstream-sync.md`.

Cannot start until Phase 1 is green.

### Phase 3 — smoke pass

Staging deploy, then a written checklist run against a scratch preprint repo.
Fixes go on a follow-up branch, never amended into the merge commit.

### Phase 4 — promotion to `main`

Maintainer's call.

## Phase 1 design: the spec harness

15 of the 20 responders are *exactly* 60 lines and structurally identical:
`keyname`, `required_params :external_call`, an `@event_regex`, and
`process_message` → `roles_and_issue?` → `process_external_service`. A diff
between any two of them shows only the class name, keyname, regex, and two
description strings. The harness exploits that.

### Tier 1 — table-driven, 15 responders

New file: `spec/responders/neurolibre/external_call_responders_spec.rb`.

A table keyed by responder class:

```ruby
{ Neurolibre::ZenodoStatusResponder => { keyname: :neurolibre_zenodo_status,
                                         matches: "@botsci zenodo status",
                                         rejects: "@botsci zenodo status now" },
  ... }
```

driving a shared example group asserting, per responder:

- `event_action` is `issue_comment.created`
- the regex matches the canonical invocation, the trailing-period variant, and
  the trailing-whitespace variant
- the regex rejects a near-miss
- `keyname` resolves in `ResponderRegistry`
- **`process_message` enqueues `ExternalServiceWorker` with the serialized
  config and locals**

That last assertion is the tripwire. `process_external_service` and
`serializable` live in `app/lib/responder.rb`, which upstream has been
changing.

The 15: `binder_build`, `build_extended_pdf`, `cache_data`,
`preprint_sync_data`, `preprint_sync_pdf`, `production_start`, `sync_myst`,
`zenodo_create_buckets`, `zenodo_flush`, `zenodo_publish`, `zenodo_status`,
`zenodo_upload_data`, `zenodo_upload_docker`, `zenodo_upload_myst`,
`zenodo_upload_repository`.

Roughly 120 lines covering three quarters of the surface.

### Tier 2 — individual specs, 4 responders + a guard path

Written in the existing `spec/responders/openjournals/` style.

- `set_archive_responder` — writes to the issue body, no `external_call`
- `set_book_responder` — same
- `preprint_server_status_responder` — 68 lines, extra branching
- `preview_server_status_responder` — same
- the `roles_and_issue?` guard on the zenodo responders: no reviewers → "Can't
  perform this without reviewers"; no editor → "Can't perform this without an
  editor". Real branching the table cannot express.

### Tier 3 — `coar_responder.rb`

200 lines, the outlier, and the newest code. Its own spec file with happy and
error coverage, alongside the 2 existing COAR specs. Its regex takes captures
(`/\A@bot coar\s+(\w+)(?:\s+from\s+(\w+))?\.?\s*$/i`), unlike every other
responder here.

### Expected outcome

~85–100 new examples across the responders, plus ~9 pinning the outbound
request. Suite goes from 774 to roughly 970.

### Policy on suspect behavior

Specs assert **what the code does today**, even where it looks wrong, with a
comment marking the spot. Suspect behaviors are collected into a separate
report at the end of Phase 1 — not fixed inline.

Rationale: a characterization suite that encodes fixes cannot tell you what the
merge changed. Fixes are a later, separately reviewable decision.

## Phase 2 design: conflict policy

| File | Resolution |
|---|---|
| `.ruby-version` | **Ours** (3.3.12). Upstream says 4.0.2 but their CI matrix is `['3.3','3.4','4.0']` — 3.3 is still supported. |
| `Gemfile` (ruby line) | **Ours.** Upstream only pins when `CUSTOM_RUBY_VERSION` is set; we default to 3.3.12 for the Heroku buildpack. |
| `Gemfile` (deps) | **Theirs** where we have no pin of our own — Sinatra/sinatra-contrib 4.1.1 → 4.2.1. |
| `Gemfile` (`ostruct`) | **Both.** Convergent fix: upstream added `gem 'ostruct'`, we added `require 'ostruct'` in `buffy_worker.rb` (3b8486e). They do not fight. |
| `.github/workflows/tests.yml` | **Ours.** Optionally add 4.0 as `failure-allowed: true` for early warning. |
| `Gemfile.lock` | **Regenerate**, do not hand-merge. |
| `app/lib/doi_checker.rb` | **Genuine two-way integration.** See below. |

### `doi_checker.rb`

The only conflict requiring real thought. Upstream restructured `check_dois`
into `handle_special_case` / `handle_missing_doi` and added a `:skip` validity
category. Our Crossref work — polite-pool `Serrano.configuration`, the
`MultiJson::ParseError` retry with backoff, `CROSSREF_LOOKUP_DELAY` between
sequential lookups — was written inside the *old* structure.

Resolution is re-applying our retry logic onto their new shape, not picking a
side. Gets its own commit and its own specs, separate from the mechanical
conflict resolutions.

### PR body

Each conflict resolution documented with its reasoning, so review is a read
rather than an archaeology exercise.

## Ongoing mechanism

`upstream` becomes a permanent remote. Future syncs:

```
git fetch upstream
git checkout -b sync/upstream-YYYY-MM
git merge upstream/main
# resolve, run suite, open PR into roboneuro/test
```

Because Phase 2 lands a real merge commit, the merge-base advances. The next
sync sees only genuinely new commits instead of re-litigating these 132.

`docs/upstream-sync.md` records the fork point, the conflict policy table, and
the 8 shared files to watch. That 8-file list is the whole risk surface and is
small enough to name explicitly.

## Verification

- **Phase 1:** suite green, ~970 examples. New specs must fail if base-class
  dispatch behavior changes — verified by temporarily breaking
  `process_external_service` and confirming red.
- **Phase 2:** same suite, same count, still green after the merge. Any
  behavioral difference shows up as a named failing example rather than a
  silent production surprise.
- **Phase 3:** smoke checklist on staging against a scratch preprint repo —
  preview build, zenodo status, myst sync, preprint sync. Specs catch
  base-class drift; only a real deploy catches Sidekiq/Heroku/env breakage.
  `zenodo publish` and `zenodo flush` are destructive and are exercised only
  against scratch records, or not at all.
