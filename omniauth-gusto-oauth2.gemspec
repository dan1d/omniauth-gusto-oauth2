# frozen_string_literal: true

require_relative 'lib/omniauth/gusto_oauth2/version'

Gem::Specification.new do |spec|
  spec.name = 'omniauth-gusto-oauth2'
  spec.version = OmniAuth::GustoOauth2::VERSION
  spec.authors = ['dan1d']
  spec.email = ['dan1d@users.noreply.github.com']

  spec.summary = 'OmniAuth OAuth2 strategy for Gusto'
  spec.description = 'An OmniAuth strategy for authenticating with Gusto payroll ' \
                     "using OAuth 2.0. Fetches user and company info via Gusto's REST API."
  spec.homepage = 'https://github.com/dan1d/omniauth-gusto-oauth2'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata = {
    'homepage_uri' => spec.homepage,
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*', 'LICENSE.txt', 'README.md', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'faraday', '>= 1.0', '< 3.0'
  spec.add_dependency 'omniauth-oauth2', '~> 1.8'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'rack-test', '~> 2.1'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.75'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.5'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'webmock', '~> 3.18'
end
