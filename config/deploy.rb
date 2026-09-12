# Capistrano 2 deployment configuration for Ergonaut.
#
# Run from a developer machine (or the Cloud9 staging box) with:
#   bundle exec cap deploy
#
# Workflow:
#   1. test changes on staging Cloud9
#   2. commit + push to origin/master
#   3. ensure local checkout matches origin (git pull)
#   4. run `bundle exec cap deploy` from the project root
#
# Notes:
# - `deploy_via :copy` packages the LOCAL working directory and uploads it.
#   Whatever you have checked out gets deployed — including uncommitted
#   changes. Keep your tree clean before deploying.
# - SSH access to deployer@www.ergosubmissions.org is required.
# - First-time-only tasks (deploy:setup, deploy:setup_config) should NOT be
#   re-run on the existing production server — they would clobber the
#   shared/config files and re-symlink nginx/init scripts.
# - See docs/staging-runbook.md for the broader staging-to-production flow.

require "bundler/capistrano"
require "rvm/capistrano"
set :whenever_command, "bundle exec whenever"
require "whenever/capistrano"

#
# CONFIG
#

set :application, "ergonaut"
#server "localhost", :web, :app, :db, primary: true #vagrant?
#server "165.227.114.9", :web, :app, :db, primary: true #staging
#server "134.122.8.104", :web, :app, :db, primary: true #staging-2020
#server "209.97.153.180", :web, :app, :db, primary: true #staging-2020-b
server "www.ergosubmissions.org", :web, :app, :db, primary: true

set :user, "deployer"
set :deploy_to, "/home/#{user}/#{application}"
#et :deploy_via, :remote_cache # from github
set :deploy_via, :copy # from local machine
#ssh_options[:port] = 2222 # vagrant only
set :use_sudo, false

set :scm, "git"
set :repository, "https://github.com/ergojournal/ergonaut.git" # remote
#set :local_repository, "file://." # vagrant only
set :branch, fetch(:branch, 'master') # "master"

set :shared_children, shared_children + %w{uploads}

default_run_options[:pty] = true
ssh_options[:forward_agent] = true


#
# TASKS
#

callback = callbacks[:after].find{|c| c.source == "deploy:assets:precompile" }
callbacks[:after].delete(callback)

# to skip precompiling assets: cap deploy -S skip_assets=true
after 'deploy:update_code', 'deploy:assets:precompile' unless fetch(:skip_assets, false)
after 'deploy', 'deploy:cleanup', 'deploy:migrate' # keep only the last 5 releases, migrate DB

namespace :deploy do
  task :cold do
    transaction do
      update
      setup_db
      start
    end
  end

  task :setup_db, roles: :app do
    raise RuntimeError.new('db:setup aborted!') unless Capistrano::CLI.ui.ask("About to `rake db:setup`. Are you sure you want to wipe the entire database (anything other than 'yes' aborts):") == 'yes'
    run "cd #{current_path}; bundle exec rake db:setup RAILS_ENV=#{rails_env}"
  end

  %w[start stop restart].each do |command|
    desc "#{command} unicorn server"
    task command, roles: :app, except: { no_release: true } do
      sudo "/home/#{user}/.rvm/bin/bootup_god #{command} unicorn_#{application}"
    end
  end

  task :setup_config, roles: :app do
    run "mkdir -p #{shared_path}/db"
    put File.read("db/seeds.rb"), "#{shared_path}/db/seeds.rb"

    sudo "ln -nfs #{current_path}/config/nginx.conf /etc/nginx/sites-enabled/#{application}"
    sudo "ln -nfs #{current_path}/config/unicorn_init.sh /etc/init.d/unicorn_#{application}"
    run "mkdir -p #{shared_path}/config"
    put File.read("config/nginx.conf"), "#{shared_path}/config/nginx.conf"
    put File.read("config/unicorn.rb"), "#{shared_path}/config/unicorn.rb"
    put File.read("config/unicorn_init.sh"), "#{shared_path}/config/unicorn_init.sh"
    put File.read("config/god.rb"), "#{shared_path}/config/god.rb"
    put File.read("config/database.yml"), "#{shared_path}/config/database.yml"
    puts "Now edit config/database.yml in #{shared_path}."
  end
  after "deploy:setup", "deploy:setup_config"

  task :symlink_config, roles: :app do
    run "ln -nfs #{shared_path}/db/seeds.rb #{release_path}/db/seeds.rb"
    run "ln -nfs #{shared_path}/config/nginx.conf #{release_path}/config/nginx.conf"
    run "ln -nfs #{shared_path}/config/unicorn.rb #{release_path}/config/unicorn.rb"
    run "ln -nfs #{shared_path}/config/unicorn_init.sh #{release_path}/config/unicorn_init.sh"
    run "ln -nfs #{shared_path}/config/god.rb #{release_path}/config/god.rb"
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
  end
  after "deploy:finalize_update", "deploy:symlink_config"

  # desc "Make sure local git is in sync with remote."
#   task :check_revision, roles: :web do
#     unless `git rev-parse HEAD` == `git rev-parse origin/master`
#       puts "WARNING: HEAD is not the same as origin/master"
#       puts "Run `git push` to sync changes."
#       exit
#     end
#   end
#   before "deploy", "deploy:check_revision"

  namespace :deploy do
    namespace :assets do
      task :precompile, :roles => :web, :except => { :no_release => true } do
        from = source.next_revision(current_revision)
        if releases.length <= 1 || capture("cd #{latest_release} && #{source.local.log(from)} vendor/assets/ app/assets/ | wc -l").to_i > 0
          run %Q{cd #{latest_release} && #{rake} RAILS_ENV=#{rails_env} #{asset_env} assets:precompile}
        else
          logger.info "Skipping asset pre-compilation because there were no asset changes."
        end
      end
    end
  end
end
