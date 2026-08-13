# COAR Notify

How to switch COAR Notify on for a deployed roboneuro, and what to expect when
it is off. For architecture, bot commands and API details see
[`app/coar_notify/README.md`](../app/coar_notify/README.md).

## What "off" means

COAR Notify ships disabled and stays inert until deliberately enabled. While
`COAR_NOTIFY_ENABLED` is unset:

- `/coar_notify/*` returns `503 COAR Notify is not enabled`
- no database connection is opened
- the release phase logs `COAR Notify disabled, skipping migrations` and exits 0
- every other route behaves exactly as it did before COAR existed

The code can be deployed freely without committing to running it.

## Prerequisites

COAR Notify is the only part of roboneuro that uses a relational database. If
the app has never had one, provision it first:

```bash
heroku addons:create heroku-postgresql:essential-0 -a <app>
```

`essential-0` is the cheapest plan; there is no free tier. This sets
`DATABASE_URL` automatically.

> `app.json` declares this addon, but Heroku only reads `app.json` when
> *creating* an app. It does nothing on a deploy to an existing app, so the
> command above is required.

## Enabling

Order matters. The database must exist before the switch is flipped.

```bash
# 1. credentials and the master switch
heroku config:set -a <app> \
  COAR_NOTIFY_ENABLED=true \
  COAR_OUTBOX_SECRET="$(openssl rand -hex 32)" \
  COAR_DASHBOARD_USER=<pick-a-username> \
  COAR_DASHBOARD_PASSWORD="$(openssl rand -hex 24)"

# 2. deploy, which runs the migration
git push heroku main:master
```

The second step creates the `coar_notifications` table. Watch the release output
for the migration running rather than being skipped.

If `COAR_NOTIFY_ENABLED=true` but `DATABASE_URL` is missing, the release phase
**fails the deploy** rather than letting the app boot without its table. That is
deliberate. Provision the database and push again.

## Verifying

```bash
# inbox is public by design: remote services must be able to deliver to it
curl -s -o /dev/null -w "%{http_code}\n" https://<host>/coar_notify/inbox            # 200

# outbox refuses anything without the secret
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://<host>/coar_notify/outbox   # 401

# dashboard challenges for credentials
curl -s -o /dev/null -w "%{http_code}\n" https://<host>/coar_notify/dashboard        # 401
curl -s -o /dev/null -w "%{http_code}\n" -u <user>:<pass> \
  https://<host>/coar_notify/dashboard                                               # 200
```

Then open `https://<host>/coar_notify/dashboard` in a browser and sign in.

To exercise the full receive path, post a notification to the inbox. A working
example lives at `spec/fixtures/coar_announce_review.json`:

```bash
curl -X POST -H 'Content-Type: application/ld+json' \
  --data-binary @spec/fixtures/coar_announce_review.json \
  https://<host>/coar_notify/inbox        # 201, and a row appears in the dashboard
```

## Access model

| Route | Access |
| --- | --- |
| `POST /coar_notify/inbox` | Open. Remote services deliver here. Optional IP whitelist. |
| `GET /coar_notify/inbox` | Open. Lists received notification IDs, per the LDN container model. |
| `GET /coar_notify/inbox/notifications/:id` | Open. Returns an inbound notification's payload. |
| `POST /coar_notify/outbox*` | Requires `COAR_OUTBOX_SECRET`, as `Authorization: Bearer <secret>` or a `secret` parameter. |
| `GET /coar_notify/dashboard*` | Basic auth via `COAR_DASHBOARD_USER` / `COAR_DASHBOARD_PASSWORD`. |

The inbox reads are open because they only ever serve *inbound* notifications,
which are other services' own public statements. The dashboard shows both
directions plus internal status and error messages, so it is closed.

If either dashboard credential is unset the dashboard returns 503 rather than
serving unauthenticated, and the outbox does the same without its secret. Both
fail closed on purpose: a half-configured deploy exposes nothing.

## Optional settings

| Variable | Default | Purpose |
| --- | --- | --- |
| `COAR_INBOX_URL` | `https://robo.neurolibre.org/coar_notify/inbox` | Advertised to remote services. |
| `COAR_SERVICE_ID` | `https://neurolibre.org` | Identifier in outgoing notifications. |
| `COAR_IP_WHITELIST_ENABLED` | `false` | Restricts who may POST to the inbox. |
| `COAR_ALLOWED_IPS` | empty | Comma separated, used only with the whitelist on. |
| `COAR_SQL_LOG_LEVEL` | `ERROR` | `DEBUG`, `INFO`, `WARN`, `ERROR` or `FATAL`. |

## Bot commands

Once enabled, editors can drive it from a review issue:

```
@roboneuro coar request from prereview
@roboneuro coar status
@roboneuro coar list
@roboneuro coar help
```

These come from the `neurolibre_coar` responder, declared in
`config/settings-<env>.yml` and restricted to editors.

## Turning it off

```bash
heroku config:unset COAR_NOTIFY_ENABLED -a <app>
```

The routes return 503 again on the next boot. Nothing else in the app is
affected, and the table and its rows are left untouched, so re-enabling picks up
where it left off. The database addon can stay provisioned or be removed
separately.

## Troubleshooting

**Release phase fails with "DATABASE_URL is not set".** `COAR_NOTIFY_ENABLED` is
true but no database is attached. Provision it and redeploy.

**Dashboard returns 503 with valid credentials.** One of the two variables is
missing or empty. Both are required.

**Inbox returns 403.** The IP whitelist is on and the sender is not listed in
`COAR_ALLOWED_IPS`.

**Outbox returns 503.** `COAR_OUTBOX_SECRET` is unset, so the outbox is closed
and sends nothing.
