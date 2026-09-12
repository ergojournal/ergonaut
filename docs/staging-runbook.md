# Staging Environment Runbook

A practical guide for the Ergo team on using the AWS Cloud9 staging environment
to test changes safely before deploying them to production.

---

## ⚠️ Read this first — staging contains REAL production data

The staging database is a copy of production. It contains:

- **Real author names, email addresses, and affiliations**
- **Real referee identities** (which production carefully anonymizes to authors;
  on staging those identities are visible to anyone with access)
- **Real submission manuscripts** — full PDFs, including unpublished work
- **Real editorial decisions, correspondence, and reviewer reports**
- **Real IP addresses** in the logs

Treat the staging box with **the same confidentiality posture as production**.
That means:

1. **Do not share staging access with anyone outside the editorial team.**
   No external contractors, no co-authors of submissions under review, no one
   who isn't already authorized to see production-level data.
2. **Do not take screenshots showing real names, emails, paper titles, or
   referee identities** for tickets, blog posts, demos, or social media. If
   you need to demo a feature, blur PII or use a test record you create
   manually.
3. **Do not export staging data** (CSV, SQL dumps, file copies) to any other
   machine — your laptop, an email attachment, a Google Doc, a Slack DM.
   The data should only ever live on the Cloud9 EC2 and the production
   droplet.
4. **Do not commit staging artifacts to git.** No DB dumps, no
   `database.yml`, no exported CSVs. These are gitignored already; don't
   force-add them.
5. **Triple-anonymous review breaks on staging.** Production hides referee
   identities from authors and author identities from referees through
   careful application logic. On staging, when you log in as an editor (or
   bypass auth in dev mode), all identities are visible. Don't share login
   sessions or screenshots that reveal those.
6. **Refresh data only when needed.** Each refresh re-imports current real
   PII. If you only need to test a code change, the existing snapshot is
   usually sufficient.
7. **If staging is compromised** (laptop stolen with active session, AWS
   credentials leaked, etc.), treat it as a production data exposure
   incident, not a "just dev environment" issue.

If anyone outside the immediate editorial team needs to test something,
build them a separate environment with **synthetic test data** (we can help
script this if needed) — do not hand them a Cloud9 invite to this box.

---

## TL;DR

- **Staging URL**: open via Cloud9's *Preview Running Application*. There is no public URL.
- **Production URL**: https://www.ergosubmissions.org (unchanged, runs on DigitalOcean)
- **What staging is for**: testing code, schema, or content changes against a real
  copy of production data **before** deploying to production.
- **What staging is not**: a public-facing system. Real users never see it.
- **Real PII**: yes, the staging DB has real names/emails/manuscripts. See
  the warning section above.
- **Mail safety**: staging never sends real emails. Anything the app would email
  is captured in memory only — full stop.
- **Snapshot of production data**: from `2026-05-09`. Refresh on demand (see
  "Refreshing staging data" below).

---

## What's on staging

| Item | Value |
|---|---|
| AWS account | `617229194950` |
| Region | `eu-west-2` (London) |
| Cloud9 environment name | `Ergo-Staging-Fresh-2026-05` |
| EC2 instance type | `t3.medium` (2 vCPU, 4 GB RAM, 30 GB EBS) |
| OS | Ubuntu 22.04 LTS |
| Ruby | 1.9.3-p547 (matches production) |
| Bundler | 1.17.3 |
| Rails | 3.2.13 (matches production) |
| MySQL server | 5.7.42 (production runs 5.5.41 — minor diff, see notes) |
| App path on box | `/home/ubuntu/environment/ergonaut` |
| Staging DB name | `ergonaut_staging` |
| Staging DB user | `ergonaut` |
| Staging DB password | see `config/database.yml` on the box |
| Server port | `8080` (accessed via Cloud9 preview, not public) |

The Cloud9 environment auto-hibernates after 30 minutes of inactivity to save
cost. Opening the IDE wakes it back up automatically (~1 minute boot).

---

## Accessing staging

### 1. Open the Cloud9 IDE

1. Sign in to AWS at https://617229194950.signin.aws.amazon.com/console
2. Switch region (top-right) to **Europe (London) / eu-west-2**
3. Go to https://eu-west-2.console.aws.amazon.com/cloud9/
4. Find `Ergo-Staging-Fresh-2026-05` → click **Open**

The IDE loads in your browser. The terminal is at the bottom.

### 2. View the running app

Top menu of Cloud9 IDE → **Preview** → **Preview Running Application**.

A side panel opens showing the staging Ergonaut. Click the *pop-out* icon
(the small arrow in the side panel toolbar) to open it in its own browser tab.

The URL Cloud9 gives you is a Cloud9-internal proxy — it works only while
you're signed in. There's no public URL for staging, by design.

### 3. Start the Rails server (if it's not running)

After the env wakes from hibernation, Rails won't be running. Start it:

```bash
cd ~/environment/ergonaut
RAILS_ENV=staging bundle exec rails server -b 0.0.0.0 -p 8080
```

Wait for the line `WEBrick::HTTPServer#start: pid=X port=8080`. Then refresh
the Cloud9 preview.

To run it in the background and free up the terminal:

```bash
cd ~/environment/ergonaut
nohup bundle exec rails server -e staging -b 0.0.0.0 -p 8080 > /tmp/rails.log 2>&1 &
disown
```

Check the log:

```bash
tail -f /tmp/rails.log
```

To stop the running Rails server:

```bash
pkill -f 'rails server'
```

---

## Making changes on staging

### Edit code

The Cloud9 IDE has a file tree on the left. Browse to
`~/environment/ergonaut`. Open and edit files just like VS Code. Save with
`Cmd+S` / `Ctrl+S`.

Because `staging.rb` sets `config.cache_classes = false`, **most code changes
take effect on the next page reload — no server restart needed.** Exceptions:

- Changes to `Gemfile` or `Gemfile.lock` → run `bundle install`
- Changes to `config/environments/staging.rb` or `config/application.rb` → restart Rails
- Changes to `config/routes.rb` → usually picked up on reload, but restart if weird routing happens

### Test in the browser

Refresh the Cloud9 preview tab. You see the change immediately.

Check `tail -f /tmp/rails.log` (or whatever log you started with) for errors
or stack traces.

### Database changes (migrations)

Generate and run a migration on staging:

```bash
cd ~/environment/ergonaut
RAILS_ENV=staging bundle exec rails generate migration <YourMigrationName>
# edit the generated file in db/migrate/...
RAILS_ENV=staging bundle exec rake db:migrate
```

Migrations run against the staging DB only. The schema change is captured in
`db/schema.rb` so it'll deploy with the code.

### Commit and push

The repo on Cloud9 is a normal git clone. Use git from the terminal:

```bash
cd ~/environment/ergonaut
git status
git checkout -b feature/your-change
git add path/to/files
git commit -m "Describe the change"
git push origin feature/your-change
```

For pushing to push, you'll need GitHub auth on the staging box. Easiest:
[create a GitHub Personal Access Token](https://github.com/settings/tokens)
with `repo` scope, then when git prompts for password, paste the token.
Or set up SSH keys (`ssh-keygen` on Cloud9, add the `.pub` to
github.com/settings/keys, change remote to `git@github.com:ergojournal/ergonaut.git`).

---

## Promoting changes from staging to production

The staging Cloud9 box is **also the deploy origin** for production.
`config/deploy.rb` and `Capfile` are committed in the repo, so Capistrano
runs directly from Cloud9. No separate "deploy laptop" needed.

The workflow:

```
edit on Cloud9  →  test via preview URL  →  commit + push to GitHub
                                              ↓
                                      pull origin/master locally
                                              ↓
                                       bundle exec cap deploy
                                              ↓
                                          live on prod
```

### Step 1 — commit and push from Cloud9

```bash
cd ~/environment/ergonaut
git checkout -b feature/your-change   # or work on master if you prefer
git add path/to/files
git commit -m "Describe the change"
git push origin <branch-name>
```

### Step 2 — (optional but recommended) open a pull request

Open a PR on https://github.com/ergojournal/ergonaut from your branch into
`master`. Merge after review.

### Step 3 — pull origin/master into the Cloud9 working tree

**Important**: `deploy.rb` uses `set :deploy_via, :copy`, which means
Capistrano packages the **local working directory** (Cloud9's checkout) and
uploads it. So before deploying, sync the local tree with what's on GitHub:

```bash
cd ~/environment/ergonaut
git checkout master
git pull origin master
git status   # MUST show "working tree clean" before deploying
```

If `git status` shows uncommitted changes, **those will go to production**.
That's almost never what you want. Either commit them or stash them first.

### Step 4 — deploy

```bash
cd ~/environment/ergonaut
bundle exec cap deploy
```

What Capistrano does (in order):

1. Packages the current working tree as a tarball
2. Uploads it to the prod droplet, extracts to a new timestamped release dir
3. Symlinks `current` → the new release
4. Symlinks `shared/config/{database.yml,nginx.conf,unicorn.rb,unicorn_init.sh,god.rb}` into the release
5. Runs `bundle install` on prod
6. Precompiles assets *only if* asset files changed (skip flag: `cap deploy -S skip_assets=true`)
7. Runs `rake db:migrate` (the `after 'deploy', 'deploy:migrate'` hook in deploy.rb)
8. Updates the system crontab from `config/schedule.rb` via the whenever gem
9. Restarts unicorn via `sudo bootup_god restart unicorn_ergonaut`
10. Cleans up old releases (keeps last 5)

Total time: typically 1–3 minutes for a code-only change, longer if assets
need precompilation.

### Step 5 — verify

- Visit https://www.ergosubmissions.org and check the change is live
- Tail the production unicorn log if anything looks off (you'll need to SSH
  into the droplet for that — `ssh deployer@104.236.248.179` then
  `tail -f /home/deployer/ergonaut/current/log/production.log`)
- Watch for exception emails to `a.j.wilson@bham.ac.uk` (production has
  exception_notification configured)

### Rolling back

```bash
cd ~/environment/ergonaut
bundle exec cap deploy:rollback
```

This re-symlinks `current` to the previous release and restarts unicorn.
**Caveat**: if the bad deploy ran a migration, rollback does **not** undo
the migration — only the code. For destructive migrations, restore the
database from a DigitalOcean snapshot or pre-deploy backup. **Always take
an on-demand DO snapshot before a risky migration.**

### Skipping asset precompile (faster deploy)

For changes that don't touch CSS or JS:

```bash
bundle exec cap deploy -S skip_assets=true
```

### How the SSH connection works

Cloud9 has its own RSA keypair at `~/.ssh/id_rsa` (PEM format —
required because Capistrano 2.15.5 ships with net-ssh 2.7.0, which doesn't
understand ed25519 keys or OpenSSH-format files). The matching public key is
in `deployer@~/.ssh/authorized_keys` on the prod droplet.

If `cap deploy` ever fails with `Net::SSH::AuthenticationFailed`:
1. Check the key is still in PEM format: `head -1 ~/.ssh/id_rsa` should say
   `-----BEGIN RSA PRIVATE KEY-----` (not `-----BEGIN OPENSSH PRIVATE KEY-----`)
2. Check the key still has its match on prod: `ssh-keygen -lf ~/.ssh/id_rsa.pub`,
   compare to keys on the droplet
3. Convert if needed: `ssh-keygen -p -m PEM -f ~/.ssh/id_rsa -P '' -N ''`

---

## Refreshing staging data from production

The data on staging is from `2026-05-09`. To refresh it with current production
data, follow the procedure in `docs/cloud9-setup.md`, sections 4 and 8 only:

1. SSH into the production droplet from your laptop
2. Run the `mysqldump` block (small, fast — ~50 MB compressed)
3. From Cloud9, `scp` the dump and re-import into `ergonaut_staging`
4. (Optional) Re-pull the uploads tarball if you specifically need new
   submission PDFs

The Cloud9 SSH key is already authorized on the droplet, so steps 2–3 work
from the Cloud9 terminal directly without going through your laptop.

You don't need to redo any of the setup steps (Ruby, MySQL, gems).

---

## Adding new environment variables to production

Production env vars live in `/home/deployer/.env` on the DigitalOcean droplet
(sourced by the unicorn init script and by cron). When you add a new one,
**`cap deploy` alone will NOT make unicorn pick it up.** This is non-obvious
and easy to miss — discovered when the Turnstile CAPTCHA rollout went live
without rendering the widget on prod despite the env vars being added.

### What happens by default (the trap)

The deploy ends with `sudo bootup_god restart unicorn_ergonaut`, which sends
god the `restart` command. god runs `service unicorn_ergonaut restart` for
that watch — and the unicorn init script's `restart` case does a **USR2
graceful reload**:

```sh
restart|reload)
  sig USR2 && echo reloaded OK && exit 0
  ...
```

A USR2 reload re-execs the unicorn master to pick up new code, but the new
master process **inherits its environment from the old master**, which was
inherited from god, which was started at boot (before your new env var
existed). So new env vars never reach unicorn.

You can confirm this on the droplet:

```bash
UPID=$(pgrep -f 'unicorn.*master' | head -1)
echo -n "MY_NEW_VAR in unicorn env: "
tr '\0' '\n' < /proc/$UPID/environ | grep -c '^MY_NEW_VAR='
# 0 means it's not there
```

### The fix: god stop + start (NOT god restart)

A hard `god stop` followed by `god start` makes god invoke its `w.start`
(`service unicorn_ergonaut start`) — which hits the init script's **start**
case, and the start case sources `~/.env` fresh:

```sh
CMD="cd $APP_ROOT; . /home/deployer/.env; bundle exec unicorn -D -c $APP_ROOT/config/unicorn.rb -E production"
```

From the droplet, as `deployer`:

```bash
sudo /home/deployer/.rvm/bin/bootup_god stop unicorn_ergonaut
sleep 4
sudo /home/deployer/.rvm/bin/bootup_god start unicorn_ergonaut
```

There's a ~5–15 sec window where the site is unreachable while unicorn is
down. Pick a low-traffic time, or rate-limit nginx to return 503 during the
restart if that matters.

After the start, verify the new var is in unicorn's env (see snippet above).
The count should be `1`.

### Procedure for adding a new env var to production

1. **Append to `/home/deployer/.env`** on the droplet. Use append (`>>`),
   not overwrite — don't clobber `GMAIL_USER`, `GMAIL_PASSWORD`, etc.:
   ```bash
   ssh deployer@<droplet-ip>
   cat >> ~/.env <<'EOF'
   export MY_NEW_VAR="value"
   EOF
   ```
2. **Hard-restart unicorn** via god stop+start (above).
3. **Verify** the var is in unicorn's env (snippet above).
4. **Test** the feature that depends on the var.

### Why not just `cap deploy` and hope?

`cap deploy` works for **code changes** because USR2 reload re-execs unicorn,
which re-loads Rails (new application code). But the process *environment*
isn't reset on USR2 — that's a UNIX thing, not a unicorn or god thing. So
new env vars require a true process restart.

### Related gotcha: god itself loses env if restarted

If god is ever killed and restarted (e.g. system reboot), god takes its
environment from however it was launched. If the launcher (e.g. `/etc/rc.local`
or systemd unit) doesn't source `~/.env`, god comes up with the wrong env,
and every unicorn it spawns will also have the wrong env. Verify the launcher
sources `~/.env` before god starts.

---

## What you must NOT do on staging

These are not just style preferences — these would cause real harm if violated:

1. **Don't run `whenever --update-crontab` on staging.** This would install
   the production cron jobs (defined in `config/schedule.rb`) on the Cloud9
   box. Those jobs send reminder emails. Even with mail interception,
   the cron entries assume the production directory layout and would
   pollute the system.

2. **Don't change `RAILS_ENV` to `production`** when starting the server on
   staging. The `production` environment loads `production.rb`, which
   configures Gmail SMTP and tries to send real emails. Always use
   `RAILS_ENV=staging`.

3. **Don't copy `~/.env` from the production droplet.** That file contains
   the Gmail SMTP credentials. If those land on Cloud9, the only safety net
   left is staging.rb's mail interception. Less margin.

4. **Don't commit `config/database.yml` to git.** It's already in
   `.gitignore`. The staging password should stay only on the Cloud9 box.

5. **Don't expose port 8080 publicly** (security group rule for `0.0.0.0/0`
   on port 8080). The Cloud9 preview URL is the right way to view it.

---

## Mail interception — how to verify it's working

Before letting anyone test email-triggering features (referee assignment,
reminders, password resets), verify mail is actually intercepted:

1. Open the Rails console on staging:
   ```bash
   cd ~/environment/ergonaut
   RAILS_ENV=staging bundle exec rails console
   ```
2. In the console, send a test email:
   ```ruby
   ActionMailer::Base.mail(from: 'staging@test', to: 'fake@test', subject: 'staging test', body: 'hi').deliver
   ActionMailer::Base.deliveries.last
   ```
3. The last line should print the Mail::Message object. **No SMTP attempt
   was made.** The email exists only in the in-memory `deliveries` array.
4. Confirm by checking the production droplet's Gmail outbox / Sent folder
   later — your test email should not appear there.

Run this verification any time staging.rb is edited.

---

## Cost

Approximate monthly cost with auto-hibernate at typical usage (3–4 hours/day):

| Component | Cost |
|---|---|
| EC2 t3.medium (~10% utilization with hibernate) | ~$5–8 |
| EBS 30 GB gp3 | ~$2.40 |
| Data transfer (negligible) | <$1 |
| **Total** | **~$8–12/month** |

If left running 24/7: ~$45/month. Auto-hibernate is your friend.

---

## Stopping or deleting the environment

To stop billing:

- **Idle**: Cloud9 auto-hibernates after 30 min idle. EC2 charges stop, EBS
  charges (~$2.40/mo) continue.
- **Force-stop now**: AWS console → EC2 → select the instance → Stop.
- **Delete entirely**: Cloud9 console → select env → Delete. This destroys
  the EC2, EBS, and all the data on the box. The DB dump and uploads tarball
  on the production droplet are unaffected, so you could rebuild from
  `cloud9-setup.md`.

---

## Where to go for more detail

- **Setup procedure**: `docs/cloud9-setup.md` (how this Cloud9 env was built,
  step by step, with troubleshooting)
- **App-level docs**: `README.md` (Ergonaut overview, feature summary)
- **Original 2023 setup notes**: in your Notion ("Set up Development Server",
  "Install MySQL 5.7…")
- **Production droplet**: SSH to `deployer@<droplet-ip>`, app at
  `/home/deployer/ergonaut/current`. Capistrano-managed; do not edit files
  directly there.

---

## Common questions

**Q: Can multiple people use staging at the same time?**
A: Yes. The Cloud9 IDE supports collaborative editing. Add other AWS users
to the env via Cloud9 console → *Share*.

**Q: Is the staging data updated automatically?**
A: No. It's a one-time snapshot from `2026-05-09`. Refresh manually when you
want recent data (see "Refreshing staging data").

**Q: If I make a change on staging, does it automatically go to production?**
A: No. You must commit, push to GitHub, and run your Capistrano deploy.

**Q: Can I break production by experimenting on staging?**
A: No. Staging cannot reach production's database, file storage, or email
provider. The only connection back to production is the SSH link from
Cloud9 to the droplet (used to pull data refreshes), and that's only used
by you, on demand.

**Q: What about secrets — are any production secrets on the staging box?**
A: No. Only the staging-only DB password is on the box (`config/database.yml`).
Production's Gmail credentials, AWS keys, etc. were never copied here.

**Q: I accidentally pushed to `master` and now I'm worried about the next deploy.**
A: Check `git log master` — if your commit is on master and someone runs
`cap production deploy`, that change will go live. Either revert the commit
(`git revert <sha>` and push) before anyone deploys, or coordinate with the
deployer.
