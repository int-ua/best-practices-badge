# frozen_string_literal: true

# Copyright 2015-2017, the Linux Foundation, IDA, and the
# CII Best Practices badge contributors
# SPDX-License-Identifier: MIT

# Rake tasks for BadgeApp

require 'json'

task(:default).clear.enhance %w[
  rbenv_rvm_setup
  bundle
  bundle_doctor
  bundle_audit
  generate_criteria_doc
  rubocop
  markdownlint
  rails_best_practices
  brakeman
  license_okay
  license_finder_report.html
  whitespace_check
  yaml_syntax_check
  html_from_markdown
  eslint
  report_code_statistics
  test
]
# Temporarily removed fasterer
# Waiting for Ruby 2.4 support: https://github.com/seattlerb/ruby_parser/issues/239

task(:ci).clear.enhance %w[
  rbenv_rvm_setup
  bundle_doctor
  bundle_audit
  markdownlint
  license_okay
  license_finder_report.html
  whitespace_check
  yaml_syntax_check
  report_code_statistics
]
# Temporarily removed fasterer

# Simple smoke test to avoid development environment misconfiguration
desc 'Ensure that rbenv or rvm are set up in PATH'
task :rbenv_rvm_setup do
  path = ENV['PATH']
  if !path.include?('.rbenv') && !path.include?('.rvm')
    raise RuntimeError 'Must have rbenv or rvm in PATH'
  end
end

desc 'Run Rubocop with options'
task :rubocop do
  sh 'bundle exec rubocop -D --format offenses --format progress'
end

desc 'Run rails_best_practices with options'
task :rails_best_practices do
  sh 'bundle exec rails_best_practices ' \
      '--features --spec --without-color'
end

desc 'Run brakeman'
task :brakeman do
  # Disable pager, so that "rake" can keep running without halting.
  sh 'bundle exec brakeman --quiet --no-pager'
end

desc 'Run bundle if needed'
task :bundle do
  sh 'bundle check || bundle install'
end

desc 'Run bundle doctor - check for some Ruby gem configuration problems'
task :bundle_doctor do
  sh 'bundle doctor'
end

desc 'Report code statistics'
task :report_code_statistics do
  verbose(false) do
    sh <<-REPORT_CODE_STATISTICS
      echo
      direct=$(sed -e '1,/^DEPENDENCIES/d' -e '/^RUBY VERSION/,$d' \
                   -e '/^$/d' Gemfile.lock | wc -l)
      indirect=$(bundle show | tail -n +2 | wc -l)
      echo "Number of gems (direct dependencies only) = $direct"
      echo "Number of gems (including indirect dependencies) = $indirect"
      echo
      rails stats
      echo
      true
    REPORT_CODE_STATISTICS
  end
end

# rubocop: disable Metrics/BlockLength
desc 'Run bundle-audit - check for known vulnerabilities in dependencies'
task :bundle_audit do
  verbose(true) do
    sh <<-RETRY_BUNDLE_AUDIT_SHELL
      apply_bundle_audit=t
      if ping -q -c 1 github.com > /dev/null 2> /dev/null ; then
        echo "Have network access, trying to update bundle-audit database."
        tries_left=10
        while [ "$tries_left" -gt 0 ] ; do
          if bundle exec bundle-audit update ; then
            echo 'Successful bundle-audit update.'
            break
          fi
          sleep 2
          tries_left=$((tries_left - 1))
          echo "Bundle-audit update failed. Number of tries left=$tries_left"
        done
        if [ "$tries_left" -eq 0 ] ; then
          echo "Bundle-audit update failed after multiple attempts. Skipping."
          apply_bundle_audit=f
        fi
      else
        echo "Cannot update bundle-audit database; using current data."
      fi
      if [ "$apply_bundle_audit" = 't' ] ; then
        bundle exec bundle-audit check
      else
        true
      fi
    RETRY_BUNDLE_AUDIT_SHELL
  end
end
# rubocop: enable Metrics/BlockLength

# Note: If you don't want mdl to be run on a markdown file, rename it to
# end in ".markdown" instead.  (E.g., for markdown fragments.)
desc 'Run markdownlint (mdl) - check for markdown problems on **.md files'
task :markdownlint do
  style_file = 'config/markdown_style.rb'
  sh "bundle exec mdl -s #{style_file} *.md doc/*.md"
end

# Apply JSCS to look for issues in JavaScript files.
# To use, must install jscs; the easy way is to use npm, and at
# the top directory of this project run "npm install jscs".
# This presumes that the jscs executable is installed in "node_modules/.bin/".
# See http://jscs.info/overview
#
# This not currently included in default "rake"; it *works* but is very
# noisy.  We need to determine which ruleset to apply,
# and we need to fix the JavaScript to match that.
# We don't scan 'app/assets/javascripts/application.js';
# it is primarily auto-generated code + special directives.
desc 'Run jscs - JavaScript style checker'
task :jscs do
  jscs_exe = 'node_modules/.bin/jscs'
  jscs_options = '--preset=node-style-guide -m 9999'
  jscs_files = 'app/assets/javascripts/project-form.js'
  sh "#{jscs_exe} #{jscs_options} #{jscs_files}"
end

desc 'Load current self.json'
task :load_self_json do
  require 'open-uri'
  require 'json'
  url = 'https://master.bestpractices.coreinfrastructure.org/projects/1.json'
  contents = open(url).read
  pretty_contents = JSON.pretty_generate(JSON.parse(contents))
  File.write('doc/self.json', pretty_contents)
end

# We use a file here because we do NOT want to run this check if there's
# no need.  We use the file 'license_okay' as a marker to record that we
# HAVE run this program locally.
desc 'Examine licenses of reused components; see license_finder docs.'
file 'license_okay' => ['Gemfile.lock', 'doc/dependency_decisions.yml'] do
  sh 'bundle exec license_finder && touch license_okay'
end

desc 'Create license report'
file 'license_finder_report.html' =>
     ['Gemfile.lock', 'doc/dependency_decisions.yml'] do
  sh 'bundle exec license_finder report --format html ' \
     '> license_finder_report.html'
end

desc 'Check for trailing whitespace in latest proposed (git) patch.'
task :whitespace_check do
  if ENV['CI'] # CircleCI modifies database.yml
    sh "git diff --check -- . ':!config/database.yml'"
  else
    sh 'git diff --check'
  end
end

desc 'Check YAML syntax (except project.yml, which is not straight YAML)'
task :yaml_syntax_check do
  # Don't check "project.yml" - it's not a straight YAML file, but instead
  # it's processed by ERB (even though the filename doesn't admit it).
  sh "find . -name '*.yml' ! -name 'projects.yml' " \
     "! -path './vendor/*' -exec bundle exec yaml-lint {} + | " \
     "grep -v '^Checking the content of' | grep -v 'Syntax OK'"
end

# The following are invoked as needed.

desc 'Create visualization of gem dependencies (requires graphviz)'
task :bundle_viz do
  sh 'bundle viz --version --requirements --format svg'
end

desc 'Deploy current origin/master to staging'
task deploy_staging: :production_to_staging do
  sh 'git checkout staging && git pull && ' \
     'git merge --ff-only origin/master && git push && git checkout master'
end

desc 'Deploy current origin/staging to production'
task :deploy_production do
  sh 'git checkout production && git pull && ' \
     'git merge --ff-only origin/staging && git push && git checkout master'
end

rule '.html' => '.md' do |t|
  sh "script/my-markdown \"#{t.source}\" | script/my-patch-html > \"#{t.name}\""
end

markdown_files = Rake::FileList.new('*.md', 'doc/*.md')

# Use this task to locally generate HTML files from .md (markdown)
task 'html_from_markdown' => markdown_files.ext('.html')

file 'doc/criteria.md' =>
     [
       'criteria/criteria.yml', 'config/locales/en.yml',
       'doc/criteria-header.markdown', 'doc/criteria-footer.markdown',
       './gen_markdown.rb'
     ] do
  sh './gen_markdown.rb'
end

# Name task so we don't have to use the filename
task generate_criteria_doc: 'doc/criteria.md' do
end

desc 'Use fasterer to report Ruby constructs that perform poorly'
task :fasterer do
  sh 'fasterer'
end

# rubocop: disable Metrics/BlockLength
# Tasks for Fastly including purging and testing the cache.
namespace :fastly do
  # Implement full purge of Fastly CDN cache.  Invoke using:
  #   heroku run --app HEROKU_APP_HERE rake fastly:purge
  # Run this if code changes will cause a change in badge level, since otherwise
  # the old badge levels will keep being displayed until the cache times out.
  # See: https://robots.thoughtbot.com/
  # a-guide-to-caching-your-rails-application-with-fastly
  desc 'Purge Fastly cache (takes about 5s)'
  task :purge do
    puts 'Starting full purge of Fastly cache (typically takes about 5s)'
    require Rails.root.join('config', 'initializers', 'fastly')
    FastlyRails.client.get_service(ENV.fetch('FASTLY_SERVICE_ID')).purge_all
    puts 'Cache purged'
  end

  desc 'Test Fastly Caching'
  task :test, [:site_name] do |_t, args|
    args.with_defaults site_name:
      'https://master.bestpractices.coreinfrastructure.org/projects/1/badge'
    puts 'Starting test of Fastly caching'
    verbose(false) do
      sh <<-PURGE_FASTLY_SHELL
        site_name="#{args.site_name}"
        echo "Purging Fastly cache of badge for ${site_name}"
        curl -X PURGE "$site_name" || exit 1
        if curl -svo /dev/null "$site_name" 2>&1 | grep 'X-Cache: MISS' ; then
          echo "Fastly cache of badge for project 1 successfully purged."
        else
          echo "Failed to purge badge for project 1 from Fastly cache."
          exit 1
        fi
        if curl -svo /dev/null "$site_name" 2>&1 | grep 'X-Cache: HIT' ; then
          echo "Fastly cache successfully restored."
        else
          echo "Fastly failed to restore cache."
          exit 1
        fi
      PURGE_FASTLY_SHELL
    end
  end
end
# rubocop: enable Metrics/BlockLength

desc 'Drop development database'
task :drop_database do
  puts 'Dropping database development'
  # Command from http://stackoverflow.com/a/13245265/1935918
  sh "echo 'SELECT pg_terminate_backend(pg_stat_activity.pid) FROM " \
     'pg_stat_activity WHERE datname = current_database() AND ' \
     "pg_stat_activity.pid <> pg_backend_pid();' | psql development; " \
     'dropdb -e development'
end

desc 'Copy database from production into development (requires access privs)'
task :pull_production do
  puts 'Getting production database'
  Rake::Task['drop_database'].reenable
  Rake::Task['drop_database'].invoke
  sh 'heroku pg:pull DATABASE_URL development --app production-bestpractices'
  Rake::Task['db:migrate'].reenable
  Rake::Task['db:migrate'].invoke
end

# Don't use this one unless you need to
desc 'Copy active production database into development (if normal one fails)'
task :pull_production_alternative do
  puts 'Getting production database (alternative)'
  sh 'heroku pg:backups:capture --app production-bestpractices && ' \
     'curl -o db/latest.dump `heroku pg:backups:public-url ' \
     '     --app production-bestpractices` && ' \
     'rake db:reset && ' \
     'pg_restore --verbose --clean --no-acl --no-owner -U `whoami` ' \
     '           -d development db/latest.dump'
end

desc 'Copy active master database into development (requires access privs)'
task :pull_master do
  puts 'Getting master database'
  Rake::Task['drop_database'].reenable
  Rake::Task['drop_database'].invoke
  sh 'heroku pg:pull DATABASE_URL development --app master-bestpractices'
  Rake::Task['db:migrate'].reenable
  Rake::Task['db:migrate'].invoke
end

# This just copies the most recent backup of production; in almost
# all cases this is adequate, and this way we don't disturb production
# unnecessarily.  If you want the current active database, you can
# force a backup with:
# heroku pg:backups:capture --app production-bestpractices
desc 'Copy production database backup to master, overwriting master database'
task :production_to_master do
  sh 'heroku pg:backups:restore $(heroku pg:backups:public-url ' \
     '--app production-bestpractices) DATABASE_URL --app master-bestpractices'
  sh 'heroku run:detached bundle exec rake db:migrate ' \
     '--app master-bestpractices'
end

desc 'Copy production database backup to staging, overwriting staging database'
task :production_to_staging do
  sh 'heroku pg:backups:restore $(heroku pg:backups:public-url ' \
     '--app production-bestpractices) DATABASE_URL ' \
     '--app staging-bestpractices --confirm staging-bestpractices'
  sh 'heroku run:detached bundle exec rake db:migrate ' \
     '--app staging-bestpractices'
end

# require 'rails/testtask.rb'
# Rails::TestTask.new('test:features' => 'test:prepare') do |t|
#   t.pattern = 'test/features/**/*_test.rb'
# end

task 'test:features' => 'test:prepare' do
  $LOAD_PATH << 'test'
  Minitest.rake_run(['test/features'])
end

# This gem isn't available in production
# Use string comparison, because Rubocop doesn't know about fake_production
if Rails.env.production? || Rails.env == 'fake_production'
  task :eslint do
    puts 'Skipping eslint checking in production (libraries not available).'
  end
else
  require 'eslintrb/eslinttask'
  Eslintrb::EslintTask.new :eslint do |t|
    t.pattern = 'app/assets/javascripts/*.js'
    # If you modify the exclude_pattern, also modify file .eslintignore
    t.exclude_pattern = 'app/assets/javascripts/application.js'
    t.options = :eslintrc
  end
end

desc 'Stub do-nothing jobs:work task to eliminate Heroku log complaints'
task 'jobs:work' do
end

desc 'Run in fake_production mode'
# This tests the asset pipeline
task :fake_production do
  sh 'RAILS_ENV=fake_production bundle exec rake assets:precompile'
  sh 'RAILS_ENV=fake_production bundle check || bundle install'
  sh 'RAILS_ENV=fake_production rails server -p 4000'
end

def normalize_values(input)
  input.transform_values! do |value|
    if value.is_a?(Hash)
      normalize_values value
    elsif value.is_a?(String)
      normalize_string value
    elsif value.is_a?(NilClass)
      value
    else raise TypeError 'Not Hash, String or NilClass'
    end
  end
end

# rubocop:disable Metrics/MethodLength
def normalize_string(value)
  # Remove trailing whitespace
  value.sub!(/\s+$/, '')
  return value unless value.include?('<')

  # Google Translate generates html text that has predictable errors.
  # The last entry mitigates the target=... vulnerability.  We don't need
  # to "counter" attacks from ourselves, but it does no harm and it's
  # easier to protect against everything.
  value.gsub(/< a /, '<a ')
       .gsub(/< \057/, '</')
       .gsub(/<\057 /, '</')
       .gsub(/<Strong>/, '<strong>')
       .gsub(/<Em>/, '<em>')
       .gsub(/ Href *=/, 'href=')
       .gsub(/href = /, 'href=')
       .gsub(/class = /, 'class=')
       .gsub(/target = /, 'target=')
       .gsub(/target="_blank" *>/, 'target="_blank" rel="noopener">')
       .gsub(%r{https: // }, 'https://')
end
# rubocop:enable Metrics/MethodLength

def normalize_yaml(path)
  # Reformats with a line-width of 80, removes trailing whitespace from all
  # values and fixes some predictable errors automatically.
  require 'yaml'
  Dir[path].each do |filename|
    normalized = normalize_values(YAML.load_file(filename))
    IO.write(
      filename, normalized.to_yaml(line_width: 60).gsub(/\s+$/, '')
    )
  end
end

desc "Ensure you're on master branch"
task :ensure_master do
  raise StandardError, 'Must be on master branch to proceed' unless
    `git rev-parse --abbrev-ref HEAD` == "master\n"

  puts 'On master branch, proceeding...'
end

desc 'Reformat en.yml'
task :reformat_en do
  normalize_yaml Rails.root.join('config', 'locales', 'en.yml')
end

desc 'Fix locale text'
task :fix_localizations do
  normalize_yaml Rails.root.join('config', 'locales', 'translation.*.yml')
end

desc 'Save English translation file as .ORIG file'
task :backup_en do
  FileUtils.cp Rails.root.join('config', 'locales', 'en.yml'),
               Rails.root.join('config', 'locales', 'en.yml.ORIG'),
               preserve: true # this is the equivalent of cp -p
end

desc 'Restore English translation file from .ORIG file'
task :restore_en do
  FileUtils.mv Rails.root.join('config', 'locales', 'en.yml.ORIG'),
               Rails.root.join('config', 'locales', 'en.yml')
end

# The "translation:sync" task syncs up the translations, but uses the usual
# YAML writer, which writes out trailing whitespace.  It should not do that,
# and the trailing whitespace causes later failures in testing, so we fix.
# Problem already reported:
# - https://github.com/aurels/translation-gem/issues/13
# - https://github.com/yaml/libyaml/issues/46
# We save and restore the en version around the sync to resolve.
# Ths task only runs in development, since the gem is only loaded then.
if Rails.env.development?
  Rake::Task['translation:sync'].enhance %w[ensure_master backup_en] do
    at_exit do
      Rake::Task['restore_en'].invoke
      Rake::Task['fix_localizations'].invoke
      puts "Now run: git commit -sam 'rake translation:sync'"
    end
  end
end

desc 'Fix Gravatar use_gravatar fields for local users'
task fix_use_gravatar: :environment do
  User.where(provider: 'local').find_each do |u|
    actually_exists = u.gravatar_exists
    if u.use_gravatar != actually_exists # Changed result - set and store
      # Use "update_column" so that updated_at isn't changed, and also
      # to do things more quickly.  There are no model validations that
      # can be affected setting this boolean value, so let's skip them.
      # rubocop: disable Rails/SkipsModelValidations
      u.update_column(:use_gravatar, actually_exists)
      # rubocop: enable Rails/SkipsModelValidations
    end
  end
end

require 'net/http'
# Request uri, reply true if fetchable. Follow redirects 'limit' times.
# See: https://docs.ruby-lang.org/en/2.0.0/Net/HTTP.html
# rubocop:disable Metrics/MethodLength
def fetchable?(uri_str, limit = 10)
  return false if limit <= 0

  # Use GET, not HEAD. Some websites will say a page doesn't exist when given
  # a HEAD request, yet will redirect correctly on a GET request. Ugh.
  response = Net::HTTP.get_response(URI.parse(uri_str))
  case response
  when Net::HTTPSuccess then
    return true
  when Net::HTTPRedirection then
    # Recurse, because redirection might be to a different site
    location = response['location']
    warn "    redirected to <#{location}>"
    return fetchable?(location, limit - 1)
  else
    return false
  end
end
# rubocop:enable Metrics/MethodLength

def link_okay?(link)
  return false if link.blank?
  # '%{..}' is used when we generate URLs, presume they're okay.
  return true if link.start_with?('mailto:', '/', '#', '%{')
  # Shortcut: If we have anything other than http/https, it's wrong.
  return false unless link.start_with?('https://', 'http://')
  # Quick check - if there's a character other than URI-permitted, fail.
  # Note that space isn't included (including space is a common error).
  return false if %r{[^-A-Za-z0-9_\.~!*'\(\);:@\&=+\$,\/\?#\[\]%]}.match?(link)

  warn "  <#{link}>"
  fetchable?(link)
end

require 'set'
def validate_links_in_string(translation, from, seen)
  translation.scan(/href=["'][^"']+["']/).each do |snippet|
    link = snippet[6..-2]
    next if seen.include?(link) # Already seen it, don't complain again.

    if link_okay?(link)
      seen.add(link)
    else
      # Don't add failures to what we've seen, so that we report all failures
      puts "\nFAILED LINK IN #{from.join('.')} : <#{link}>"
    end
  end
end

# Recursive validate links.  "seen" refers to a set of links already seen.
# To recurse we really want kind_of?, not is_a?, so disable rubocop rule
# rubocop:disable Style/ClassCheck
def validate_links(translation, from, seen)
  if translation.kind_of?(Array)
    translation.each_with_index do |i, part|
      validate_links(part, from + [i], seen)
    end
  elsif translation.kind_of?(Hash)
    translation.each { |key, part| validate_links(part, from + [key], seen) }
  elsif translation.kind_of?(String) # includes safe_html
    validate_links_in_string(translation.to_s, from, seen)
  end
end
# rubocop:enable Style/ClassCheck

desc 'Validate hypertext links'
task validate_hypertext_links: :environment do
  seen = Set.new # Track what we've already seen (we'll skip them)
  I18n.available_locales.each do |loc|
    validate_links I18n.t('.', locale: loc), [loc], seen
  end
end

# Convert project.json -> project.sql (a command to re-insert data).
# This only *generates* a SQL command; I did it this way so that it's easy
# to check the command to be run *before* executing it, and this also makes
# it easy to separately determine the database to apply the command to.
# Note that this depends on non-standard PostgreSQL extensions.
desc 'Convert file "project.json" into SQL insertion command in "project.sql".'
task :create_project_insertion_command do
  puts 'Reading file project.json (this uses PostgreSQL extensions)'
  file_contents = File.read('project.json')
  data_hash = JSON.parse(file_contents)
  project_id = data_hash['id']
  puts "Inserting project id #{project_id}"
  # Escape JSON using SQL escape ' -> '', so we can use it in a SQL command
  escaped_json = "'" + file_contents.gsub(/'/, "''") + "'"
  sql_command = 'insert into projects select * from ' \
                "json_populate_record(NULL::projects, #{escaped_json});"
  File.write('project.sql', sql_command)
  puts 'File project.sql created. To use this, do the following (examples):'
  puts 'Local:  rails db < project.sql'
  puts 'Remote: heroku pg:psql --app production-bestpractices < project.sql'
end

# Use this if the badge rules change.  This will email those who
# gain/lose a badge because of the changes.
desc 'Run to recalculate all badge percentages for all projects'
task update_all_badge_percentages: :environment do
  Project.update_all_badge_percentages(Criteria.keys)
end

desc 'Run to recalculate higher-level badge percentages for all projects'
task update_all_higher_level_badge_percentages: :environment do
  Project.update_all_badge_percentages(Criteria.keys - ['0'])
end

# To change the email encryption keys:
# Set EMAIL_ENCRYPTION_KEY_OLD to old key,
# set EMAIL_ENCRYPTION_KEY and EMAIL_BLIND_INDEX_KEY to new key, and run this.
# THIS ASSUMES THAT THE DATABASE IS QUIESCENT (e.g., it's temporarily
# unavailable to users).  If you don't like that assumption, put this
# within a transaction, but you'll pay a performance price.
# Note: You *CAN* re-invoke this if a previous pass only went partway;
# we loop over all users, but ignore users where the rekey doesn't work.
desc 'Rekey (change keys) of email addresses'
task rekey: :environment do
  old_key = [ENV['EMAIL_ENCRYPTION_KEY_OLD']].pack('H*')
  User.find_each do |u|
    begin
      u.rekey(old_key) # Raises exception if there's a CipherError.
      Rails.logger.info "Rekeyed email address of user id #{u.id}"
      u.save! if u.email.present?
    rescue OpenSSL::Cipher::CipherError
      Rails.logger.info "Cannot rekey user #{u.id}"
    end
  end
end

Rake::Task['test:run'].enhance ['test:features']

# This is the task to run every day, e.g., to record statistics
# Configure your system (e.g., Heroku) to run this daily.  If you're using
# Heroku, see: https://devcenter.heroku.com/articles/scheduler
desc 'Run daily tasks used in any tier, e.g., record daily statistics'
task daily: :environment do
  ProjectStat.create!
  day_for_monthly = (ENV['BADGEAPP_DAY_FOR_MONTHLY'] || '5').to_i
  Rake::Task['monthly'].invoke if Time.now.utc.day == day_for_monthly
end

# Run this task to email a limited set of reminders to inactive projects
# that do not have a badge.
# Configure your system (e.g., Heroku) to run this daily.  If you're using
# Heroku, see: https://devcenter.heroku.com/articles/scheduler
# rubocop:disable Style/Send
desc 'Send reminders to the oldest inactive project badge entries.'
task reminders: :environment do
  puts 'Sending inactive project reminders. List of reminded project ids:'
  p ProjectsController.send :send_reminders
  true
end
# rubocop:enable Style/Send

# rubocop:disable Style/Send
desc 'Send monthly announcement of passing projects'
task monthly_announcement: :environment do
  puts 'Sending monthly announcement. List of reminded project ids:'
  p ProjectsController.send :send_monthly_announcement
  true
end
# rubocop:enable Style/Send

desc 'Run monthly tasks (called from "daily")'
task monthly: %i[environment monthly_announcement fix_use_gravatar] do
end

# Send a mass email, subject MASS_EMAIL_SUBJECT, body MASS_EMAIL_BODY.
# If you set MASS_EMAIL_WHERE, only matching records will be emailed.
# We send *separate* emails for each user, so that users won't be able
# to learn of each other's email addresses.
# We do *NOT* try to localize, for speed.
desc 'Send a mass email (e.g., a required GDPR notification)'
task :mass_email do
  subject = ENV['MASS_EMAIL_SUBJECT']
  body = ENV['MASS_EMAIL_BODY']
  where_condition = ENV['MASS_EMAIL_WHERE'] || 'true'
  raise if !subject || !body
  User.where(where_condition).find_each do |u|
    UserMailer.direct_message(u, subject, body).deliver_now
    Rails.logger.info "Mass notification sent to user id #{u.id}"
  end
end

# Run this task periodically if we want to test the
# install-badge-dev-environment script
desc 'check that install-badge-dev-environment works'
task :test_dev_install do
  puts 'Updating test-dev-install branch'
  sh <<-TEST_BRANCH_SHELL
    git checkout test-dev-install
    git merge --no-commit master
    git checkout HEAD circle.yml
    git commit -a -s -m "Merge master into test-dev-install"
    git push origin test-dev-install
    git checkout master
  TEST_BRANCH_SHELL
end

# Run some slower tests. Doing this on *every* automated test run would be
# slow things down, and the odds of them being problems are small enough
# that the slowdown is less worthwhile.  Also, some of the tests (like the
# CORS tests) can interfere with the usual test setups, so again, they
# aren't worth running in the "normal" automated tests run on each commit.
desc 'Run slow tests (e.g., CORS middleware stack location)'
task :slow_tests do
  # Test CORS library middleware stack location check in environments.
  # Because of the way it works, Rack::Cors *must* be first in the Rack
  # middleware stack, as documented here: https://github.com/cyu/rack-cors
  # This test verifies this precondition, because it'd be easy to
  # accidentally cause this assumption to fail as code is changed and
  # gems are added or updated.
  # This is a slow test (we bring up a whole environment).
  %w[production development test].each do |environment|
    command = "RAILS_ENV=#{environment} rake middleware"
    result = IO.popen(command).readlines.grep(/^use /).first.chomp
    Kernel.abort("Misordered #{command}") unless result == 'use Rack::Cors'
  end
end
