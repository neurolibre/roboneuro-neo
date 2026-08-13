source 'https://rubygems.org'

# Declared unconditionally so bundler records a RUBY VERSION in Gemfile.lock.
# Heroku's buildpack chooses the ruby to install by reading that stanza, before
# bundler ever runs, so a conditional directive leaves it on the stack default.
ruby ENV.fetch("CUSTOM_RUBY_VERSION", "3.3.12")

gem 'octokit'
gem 'sinatra', '4.1.1'
gem 'sinatra-contrib', '4.1.1'
gem 'openssl'
gem 'puma'
gem 'sidekiq'
gem 'bibtex-ruby'
gem 'faraday'
gem 'faraday-retry'
gem 'serrano'
gem 'rexml'
gem 'github-linguist'
gem 'licensee'
gem 'issue'
gem 'chronic'

# Ruby 3.4 moved bigdecimal from a default gem to a bundled one. crack, via
# webmock, requires it at runtime without declaring it, so the suite fails to
# load on 3.4 unless it is in the bundle explicitly.
gem 'bigdecimal'

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'webmock'
end

eval_gemfile './Gemfile_custom'
