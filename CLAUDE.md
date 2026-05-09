# Ergonaut — Claude Context

Peer review management system for the open-access philosophy journal *Ergo* (https://www.ergosubmissions.org). One Rails app per journal; not a generic OJS-style platform.

## Engagement context

A contractor (the user) was brought in to stand up a **dev/staging environment on AWS Cloud9** so the team can test changes before promoting to production.

Production currently runs on a DigitalOcean droplet. AWS (Cloud9) is being introduced solely for the staging environment.

### Backup decision (2026-05-08)

The user evaluated and **declined** a second-tier off-site backup. Production relies on **DigitalOcean automated weekly backups** (4-week rolling retention, full-VM images, last successful 2026-05-03) as the sole backup mechanism. RPO is up to 7 days; this is accepted.

Implications for future work:
- Don't propose an S3 backup pipeline, daily `mysqldump` cron, or off-site replication unless the user reopens the question.
- The in-repo `backup -t basic` cron in `config/schedule.rb` line 39 was left as-is, **unaudited**. We don't know if it's running or where it writes. Don't touch it.
- A 5-year-old manual snapshot named `production-liveupdatebackup` (9.2 GB, NYC3) exists in the DO account. It's stale and not load-bearing, but the user chose to leave it alone for now.

## Stack (legacy — handle with care)

- **Rails 3.2.13** (EOL — last security release was 2016). Do not casually upgrade gems; many are version-pinned for a reason.
- **Ruby**: not pinned in repo (no `.ruby-version`). Production almost certainly runs 1.9.3 or 2.0.x given Rails 3.2.13 + Capistrano 2 + `rvm-capistrano`. Confirm against the live droplet before provisioning Cloud9.
- **Database**: MySQL via `mysql2 ~> 0.3.2`. Schema has 8 tables (`users`, `submissions`, `referee_assignments`, `area_editor_assignments`, `areas`, `journal_settings`, `sent_emails`, `trigrams`). Schema version `20200830220820`.
- **App server**: `unicorn` in production, `thin` in dev. Nginx in front (uses `X-Accel-Redirect` for protected file downloads).
- **Deployment**: Capistrano 2.15.5 with `rvm-capistrano`. Deploy path on droplet: `/home/deployer/ergonaut/current`. The `deploy.rb` is not committed in standard locations — likely lives only on the droplet or in a separate ops repo.
- **File uploads**: `carrierwave` writing to **local filesystem** (not S3). S3 config is commented out in `config/initializers/carrierwave.rb` but the env vars (`AWS_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET`) are referenced. Submission PDFs and referee attachments live on the droplet's disk — **these must be included in any backup**.
- **Email**: Gmail SMTP in production (`ENV['GMAIL_USER']` / `ENV['GMAIL_PASSWORD']`). Mailcatcher (localhost:1025) in dev. Exception emails go to `a.j.wilson@bham.ac.uk`.
- **Background work**: No Sidekiq/Resque. The `whenever` gem compiles `config/schedule.rb` to a system crontab; jobs run via `bin/rails runner`. Cron sources `~/.env` on the droplet for credentials.
- **Tests**: RSpec 2.14, Capybara, Factory Girl, Database Cleaner, Poltergeist (PhantomJS — itself EOL).

## Environment variables (production)

Set on the droplet via `~/.env`, sourced by cron and Capistrano:

- `GMAIL_USER`, `GMAIL_PASSWORD` — SMTP for outgoing mail
- `AWS_ACCESS_KEY`, `AWS_SECRET_ACCESS_KEY`, `AWS_S3_BUCKET` — referenced but currently unused (S3 storage is commented out)
- Database credentials — `config/database.yml` is **not in the repo** (gitignored); it lives on the droplet

## Production specifics

- Hostname: `www.ergosubmissions.org`
- Mailer host configured in `config/environments/production.rb`
- Force SSL is on
- Triple-anonymous review workflow: handling editors, referees, and authors are mutually anonymized — be careful with any data dumps that could leak identities into staging

## Working in this repo

- Don't add Docker / docker-compose unless asked — the team's deployment story is Capistrano-based and changing it is out of scope.
- Don't bump Rails or major gems. Bundler resolution on this stack is fragile; gem servers may not even serve old binaries cleanly anymore.
- `db/schema.rb` is the source of truth for the schema; don't generate new migrations without a reason.
- Tests run with RSpec 2 syntax (`describe`, `it`, `before(:each)`) — not RSpec 3+.
- Repo: `git@github.com:ergojournal/ergonaut.git`, branch `master`. Most recent code activity ~2020.

## Priorities right now

**Cloud9 staging.** Provision an EC2-backed Cloud9 env, install matching Ruby, MySQL client, bundle Rails 3.2.13, and restore a **sanitized** copy of the production data (real schema, scrubbed PII for non-public fields if the team agrees) so they have a realistic place to test. Production data gets into staging via a one-time `mysqldump` + `scp` from the droplet — there is no ongoing data sync pipeline to build.

Recommended hygiene before any work that touches production: have the user take a one-click on-demand DO snapshot ("Take a Snapshot" on the Backups & Snapshots tab) as a freeze point.
