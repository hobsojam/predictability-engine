# frozen_string_literal: true

source 'https://rubygems.org'

# Use the gemspec for dependencies
gemspec

# Internal cbp-org gems — only available in local dev and internal CI.
# GitHub Actions workflows set JIRA_ENV=gha; this block is skipped there
# so the source never enters Bundler's resolution path.
unless ENV['JIRA_ENV'] == 'gha'
  source 'https://gems.cbp-org.internal' do
    gem 'badge-service-cli'
  end
end
