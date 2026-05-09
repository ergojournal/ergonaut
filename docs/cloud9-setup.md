# AWS Cloud9 Staging Setup for Ergonaut

How to spin up an AWS Cloud9 environment that runs the Ergonaut Rails 3.2.13 app
with a copy of real production data, for safe testing before deploying to prod.

Production runs on a single DigitalOcean droplet (`www.ergosubmissions.org`).
Staging is **separate** — a Cloud9 environment in AWS, populated by a one-time
data dump from prod.

> **Mail interception is mandatory in staging.** Production data contains real
> author/referee/editor email addresses. Any notification fired from staging
> with default delivery would land in a real user's inbox. The `staging.rb`
> environment config below sets `delivery_method = :test` for this reason.
> **Do not** install `whenever`'s crontab on staging; that would fire reminder
> emails to real users on a schedule.

---

## Prerequisites

- AWS account with Cloud9 enabled (account 617229194950 is grandfathered;
  AWS stopped accepting new Cloud9 customers after July 2024 — existing
  accounts can still create environments)
- SSH access to the production droplet (`deployer@<droplet-ip>`)
- The droplet's IP address (find on the DigitalOcean Overview tab)
- A local terminal (macOS / Linux / Windows WSL) with `ssh` and `scp`

Recommended before starting any staging work that will touch production:
take a manual on-demand snapshot of the production droplet via the DO console
(*Backups & Snapshots → Take a Snapshot*) as a freeze-point.

---

## 1. Create the Cloud9 environment

In the AWS console:

1. Region: **Europe (London) / eu-west-2** (matches what the team has used)
2. Cloud9 → Create environment
3. Settings:
   - **Name**: `Ergo-Staging-<YYYY-MM>`
   - **Environment type**: New EC2 instance
   - **Instance type**: `t3.medium` (4 GB RAM — `t2.micro` is too small,
     bundle install OOM-kills routinely)
   - **Platform**: Ubuntu Server 22.04 LTS (only option offered)
   - **Connection**: AWS Systems Manager (SSM) — preferred over SSH,
     no inbound port 22 needed
   - **Cost-saving setting**: After 30 minutes idle (auto-hibernate keeps
     monthly cost ~$5–10 with typical use)

After the env spins up (~3 min), open the IDE.

## 2. Resize the EBS volume (10 GB → 30 GB)

The Cloud9 default disk is 10 GB, which is not enough for OS + Ruby +
production uploads (~7.8 GB) + bundle gems.

**Part A — modify the volume in the EC2 console:**

1. https://eu-west-2.console.aws.amazon.com/ec2/home?region=eu-west-2#Volumes:
2. Find the volume named `aws-cloud9-Ergo-Staging-...`
3. Right-click → Modify volume → Size: `30` GiB → Modify
4. Wait until state shows `in-use - optimizing` (~1 min)

**Part B — grow the filesystem from the Cloud9 terminal:**

```bash
ROOT_DEV=$(findmnt -n -o SOURCE / | sed 's/p\?[0-9]*$//')
ROOT_PART=$(findmnt -n -o SOURCE /)
PART_NUM=$(echo "$ROOT_PART" | grep -oE '[0-9]+$')

sudo growpart "$ROOT_DEV" "$PART_NUM"
sudo resize2fs "$ROOT_PART"
df -h /
```

`df -h /` should now show ~30 G total.

## 3. Set up SSH from Cloud9 to the production droplet

Generate a keypair on the Cloud9 EC2:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "cloud9-staging"
cat ~/.ssh/id_ed25519.pub
```

Copy the printed line (one line starting with `ssh-ed25519`). On the
production droplet (via your laptop's SSH session, or via DigitalOcean's
browser console as `deployer`), append it to authorized_keys:

```bash
echo 'ssh-ed25519 ... cloud9-staging' >> ~/.ssh/authorized_keys
```

Test from Cloud9:

```bash
ssh -o StrictHostKeyChecking=accept-new deployer@<droplet-ip> "hostname && whoami"
```

Should print `production` and `deployer`.

> If `Permission denied (publickey)`: verify the key actually landed in
> `~deployer/.ssh/authorized_keys` on the droplet. Note that `ssh-keygen -lf`
> only shows the *first* key on older OpenSSH; use `wc -l ~/.ssh/authorized_keys`
> instead.

## 4. Pull production data

The droplet's `/tmp` only has ~10 GB free, so we stream the 7.8 GB uploads
directly from droplet to Cloud9 instead of staging them on disk.

**Database dump** (run on the droplet via your SSH session):

```bash
cd /home/deployer/ergonaut/current

# Read DB creds from database.yml into a private file (keeps them out of `ps`)
TMPCNF=$(mktemp /tmp/.dbcnf.XXXXXX) && chmod 600 "$TMPCNF"
ruby -ryaml -e 'c = YAML.load_file("config/database.yml")["production"]; puts "[client]"; puts "user="+c["username"]; puts "password="+c["password"]' > "$TMPCNF"

mysqldump --defaults-extra-file="$TMPCNF" \
  --single-transaction --quick --routines --triggers \
  ergonaut | gzip > /tmp/ergonaut_prod_$(date +%F).sql.gz

rm -f "$TMPCNF"
ls -lh /tmp/ergonaut_prod_*.sql.gz
sha256sum /tmp/ergonaut_prod_*.sql.gz
```

**Pull DB dump to Cloud9** (run in the Cloud9 terminal):

```bash
scp deployer@<droplet-ip>:/tmp/ergonaut_prod_*.sql.gz ~/
sha256sum ~/ergonaut_prod_*.sql.gz   # confirm matches the one on droplet
```

**Stream uploads tarball** (run on Cloud9 — no /tmp staging on droplet):

> Important: `current/uploads` is a Capistrano symlink to `shared/uploads`.
> Tar must follow the symlink target, otherwise it archives only the
> symlink entry (~10 KB). Use the `shared/` path directly.

```bash
ssh deployer@<droplet-ip> "tar -cf - -C /home/deployer/ergonaut/shared uploads/" \
  > ~/ergonaut_uploads_$(date +%F).tar
ls -lh ~/ergonaut_uploads_*.tar    # should be ~7.8 G
```

Takes 5–15 min depending on bandwidth. The terminal stays silent until done.

## 5. Install system packages

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential libssl-dev libreadline-dev zlib1g-dev \
  git nodejs \
  libxml2-dev libxslt1-dev libffi-dev libgdbm-dev libncurses5-dev \
  pkg-config curl autoconf bison
```

> Do **not** install `mysql-server` or `default-libmysqlclient-dev` from
> Ubuntu's repos. Ubuntu 22.04's defaults are MySQL 8.0 / MariaDB 3.x, which
> removed the `my_bool` type and `MYSQL_SECURE_AUTH` constant that mysql2
> 0.3.x assumes exist. We need MySQL 5.7 specifically — see step 7.

## 6. Install Ruby 1.9.3-p547 via rbenv

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
source ~/.bashrc

rbenv install 1.9.3-p547
```

ruby-build automatically downloads and bundles OpenSSL 1.0.2u alongside
Ruby — modern OpenSSL 1.1+ is incompatible with Ruby 1.9.3 without patches.
Build takes ~15–25 min total (OpenSSL + Ruby).

Pin the project to this Ruby:

```bash
cd ~/environment/ergonaut
rbenv local 1.9.3-p547
ruby -v   # should print 1.9.3p547
```

## 7. Install MySQL 5.7 (NOT 8.0)

This is the load-bearing version pin. MySQL 8.0's client library removed
`my_bool` and `MYSQL_SECURE_AUTH`, breaking the mysql2 0.3.x gem build.
MySQL 5.7's client library still has the old C API.

> The previous developer (per Notion docs) used MySQL 5.7.30. We use the
> latest 5.7.x available from Oracle's apt repo (5.7.42 as of this writing).

```bash
# Add MySQL's apt config (auto-answers the dialog: bionic + mysql-5.7)
cd /tmp
wget https://dev.mysql.com/get/mysql-apt-config_0.8.12-1_all.deb

echo "mysql-apt-config mysql-apt-config/repo-codename select bionic" | sudo debconf-set-selections
echo "mysql-apt-config mysql-apt-config/repo-distro select ubuntu" | sudo debconf-set-selections
echo "mysql-apt-config mysql-apt-config/select-server select mysql-5.7" | sudo debconf-set-selections
echo "mysql-apt-config mysql-apt-config/select-product select Ok" | sudo debconf-set-selections

DEBIAN_FRONTEND=noninteractive sudo -E dpkg -i mysql-apt-config_0.8.12-1_all.deb

# Import the (current) MySQL signing key — the older 467B... key is no longer used
gpg --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C
gpg --export --armor B7B3B788A8D3785C | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/mysql-new.gpg

sudo apt update
```

Pre-seed the root password and install the 5.7 server:

```bash
echo "mysql-community-server mysql-community-server/root-pass password Ergo_Staging_2026#" | sudo debconf-set-selections
echo "mysql-community-server mysql-community-server/re-root-pass password Ergo_Staging_2026#" | sudo debconf-set-selections

DEBIAN_FRONTEND=noninteractive sudo -E apt install -y -f \
  'mysql-client=5.7*' 'mysql-community-server=5.7*' 'mysql-server=5.7*'
```

> **Critical step**: install the dev headers from the 5.7 repo, not from
> Ubuntu main. Without a version pin, `apt install libmysqlclient-dev` grabs
> Ubuntu's 8.0.x package, and you'll get the same compile errors. Verify
> with `mysql_config --version` — must say `5.7.x`, not `8.0.x`.

```bash
# If Ubuntu's 8.0 dev headers got pulled in, purge them first
sudo apt-get purge -y libmysqlclient-dev libmysqlclient21 2>/dev/null

sudo apt-get install -y 'libmysqlclient-dev=5.7*'

mysql_config --version    # MUST show 5.7.x — block here if it doesn't
grep -l my_bool /usr/include/mysql/*.h | head -3   # must find at least one file
```

## 8. Restore production data into MySQL 5.7

```bash
mysql -u root -p'Ergo_Staging_2026#' -e \
  "CREATE DATABASE ergonaut_staging CHARACTER SET utf8mb4;"
mysql -u root -p'Ergo_Staging_2026#' -e \
  "CREATE USER 'ergonaut'@'localhost' IDENTIFIED BY 'Ergo_Staging_2026#';"
mysql -u root -p'Ergo_Staging_2026#' -e \
  "GRANT ALL PRIVILEGES ON ergonaut_staging.* TO 'ergonaut'@'localhost';"

gunzip < ~/ergonaut_prod_*.sql.gz | \
  mysql -u ergonaut -p'Ergo_Staging_2026#' ergonaut_staging

mysql -u ergonaut -p'Ergo_Staging_2026#' ergonaut_staging -e \
  "SELECT (SELECT COUNT(*) FROM users) AS users, (SELECT COUNT(*) FROM submissions) AS submissions;"
```

The counts should match what you saw on the droplet at dump time.

## 9. Clone repo, extract uploads, install gems

```bash
cd ~/environment
git clone https://github.com/ergojournal/ergonaut.git
cd ergonaut
tar -xf ~/ergonaut_uploads_*.tar
du -sh uploads/    # should be ~7.8 G
rm -f ~/ergonaut_uploads_*.tar    # free up the duplicate
```

> Note on bundler version: production uses bundler 1.7.12, but its
> "fetch source index" phase is painfully slow (~15 min) because it uses
> the deprecated rubygems API. **Use bundler 1.17.3 instead** — it uses the
> modern compact-index API (~1 min total). The Gemfile.lock locks gem
> versions, so bundler version doesn't affect the actual gems installed.

```bash
gem install bundler -v 1.17.3 --no-ri --no-rdoc
rbenv rehash

# Bump mysql2 from 0.3.20 (prod's pin) to 0.3.21 in the lockfile.
# 0.3.20 has known compile issues even on MySQL 5.7; 0.3.21 is the last
# 0.3.x release and works reliably. Allowed by the Gemfile constraint
# `gem 'mysql2', '~> 0.3.2'`.
sed -i 's/mysql2 (0\.3\.20)/mysql2 (0.3.21)/' Gemfile.lock

bundle _1.17.3_ install --path vendor/bundle
```

Should finish in 2–4 min, with no compile errors.

## 10. Configure staging environment

Create `config/database.yml` (it's gitignored — staging copy lives only on
this Cloud9 box):

```yaml
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: 5
  timeout: 5000

test:
  adapter: sqlite3
  database: db/test.sqlite3
  pool: 5
  timeout: 5000

staging:
  adapter: mysql2
  encoding: utf8
  reconnect: false
  database: ergonaut_staging
  pool: 5
  username: ergonaut
  password: 'Ergo_Staging_2026#'
  socket: /var/run/mysqld/mysqld.sock
```

Create `config/environments/staging.rb`:

```ruby
Ergonaut::Application.configure do
  # Allow code reloading so devs can test changes without restart
  config.cache_classes = false

  # Show full error reports
  config.consider_all_requests_local       = true
  config.action_controller.perform_caching = false

  # MAIL INTERCEPTION — MANDATORY because we have real production data
  config.action_mailer.delivery_method      = :test
  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.perform_deliveries    = false
  config.action_mailer.default_url_options   = { host: 'localhost', port: 8080 }

  # On-the-fly asset compilation (no precompile step)
  config.assets.compile = true
  config.assets.debug   = true

  # Log to stdout so the Cloud9 terminal shows requests
  config.logger    = Logger.new(STDOUT)
  config.log_level = :debug
end
```

## 11. Boot the app

```bash
cd ~/environment/ergonaut
RAILS_ENV=staging bundle exec rails server -b 0.0.0.0 -p 8080
```

Open Cloud9's **Preview → Preview Running Application**. The Ergonaut
homepage should load. Log in as a real editor to verify real data is
visible.

## Verification checklist

- [ ] App boots and homepage loads in Cloud9 preview
- [ ] Row counts in staging match production (`users=11211, submissions=9646`
      or whatever the dump-time counts were)
- [ ] **Trigger an email manually** (e.g. assign a referee). Verify the
      email lands in `ActionMailer::Base.deliveries` and **not** in any
      real inbox. **This must pass before staging is considered safe to use.**
- [ ] `crontab -l` for the Cloud9 user is empty — no `whenever` jobs
      scheduled. Reminder emails would otherwise fire to real users.

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| `mysql2 0.3.x` won't compile, errors about `my_bool` and `MYSQL_SECURE_AUTH` | Wrong libmysqlclient-dev version (8.0 instead of 5.7) | `apt-get purge libmysqlclient-dev && apt-get install 'libmysqlclient-dev=5.7*'` |
| `bundle install` hangs at "Fetching source index" for 15+ minutes | Bundler 1.7.x's slow API | Switch to `bundle _1.17.3_ install` |
| `tar` produces a 10 KB tarball | `current/uploads` is a Capistrano symlink to `shared/uploads`; tar archived only the symlink | Tar from `/home/deployer/ergonaut/shared` directly, not `current` |
| Ruby 1.9.3 fails to compile against modern OpenSSL | OpenSSL 1.1+ broke Ruby 1.9 ssl extension | ruby-build now bundles OpenSSL 1.0.2u automatically — no separate step needed |
| `apt update` errors with `NO_PUBKEY B7B3B788A8D3785C` | MySQL rotated their apt signing key | Import the new key: `gpg --keyserver keyserver.ubuntu.com --recv-keys B7B3B788A8D3785C` |
| `ssh-keygen -lf authorized_keys` only shows one fingerprint | Older OpenSSH `ssh-keygen` has this limitation | Trust `wc -l authorized_keys` and the SSH connection itself |

## What's NOT included in this setup

- **CI/CD or automated deploy to staging.** This is a manually-managed sandbox.
- **Off-site backups.** Production relies on DigitalOcean's automated weekly
  backups. No second-tier off-site backup is configured.
- **Sanitization of real data.** The staging DB contains real
  author/referee/editor PII. Mail interception is the only safety mechanism;
  data scrubbing was explicitly out of scope.
- **Whenever cron jobs.** `config/schedule.rb` defines reminder email cron jobs
  that run in production. Do not run `whenever --update-crontab` on staging —
  it would email real users.

## References

- Previous developer's setup notes (Notion):
  - "Set up Development Server" — outlines what was done in 2023
  - "Install MySQL 5.7 server and client on Ubuntu 22.04 LTS Linux" — apt-config method
  - "Resource: Uninstalling MySQL" — purge commands
- Cloud9 disk resize: https://docs.aws.amazon.com/cloud9/latest/user-guide/move-environment.html#move-environment-resize
- mysql2 gem build issues on modern systems: https://github.com/brianmario/mysql2/issues
