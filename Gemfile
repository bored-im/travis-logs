# frozen_string_literal: true

source 'https://rubygems.org'

ruby '2.4.1' if ENV.key?('DYNO')

def gh(slug)
  "https://github.com/#{slug}.git"
end

gem 'activesupport'
gem 'aws-sdk'
gem 'bunny'
gem 'coder', git: gh('rkh/coder')
gem 'concurrent-ruby', require: 'concurrent'
gem 'connection_pool'
gem 'jemalloc', git: gh('joshk/jemalloc-rb')
gem 'jwt'
gem 'metriks'
gem 'metriks-librato_metrics'
gem 'multi_json'
gem 'oj'
gem 'pg'
gem 'pry'
gem 'puma'
gem 'pusher'
gem 'rack-ssl'
gem 'rack-test', group: :test
gem 'rake'
gem 'redis-namespace'
gem 'rspec', group: :test
gem 'rubocop', require: false, group: :test
gem 'sentry-raven'
gem 'sequel'
gem 'sidekiq'
gem 'simplecov', require: false, group: :test
gem 'sinatra'
gem 'sinatra-contrib'
gem 'sinatra-param'
gem 'travis-config'
gem 'travis-exceptions', git: gh('travis-ci/travis-exceptions')
gem 'travis-logger', git: gh('travis-ci/travis-logger'), ref: '1518ce2'
gem 'travis-metrics', git: gh('travis-ci/travis-metrics')
