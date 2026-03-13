# OmniAuth Gusto OAuth2 Strategy

[![Gem Version](https://badge.fury.io/rb/omniauth-gusto-oauth2.svg)](https://badge.fury.io/rb/omniauth-gusto-oauth2)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An OmniAuth strategy for authenticating with [Gusto](https://gusto.com/) using OAuth 2.0.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'omniauth-gusto-oauth2'
```

Then execute:

```bash
$ bundle install
```

## Gusto Developer Setup

1. Sign up at [Gusto Developer Portal](https://dev.gusto.com/)
2. Create a new application
3. Note your **Client ID** and **Client Secret**
4. Add your **Redirect URI** (e.g., `https://yourapp.com/auth/gusto_oauth2/callback`)

> **Important:** Only primary or full-access admins can authorize applications. Each company must be authorized through a separate OAuth flow.

### Demo vs Production

During development, use the Gusto demo environment:

| Environment | API Base URL |
|-------------|-------------|
| Demo | `https://api.gusto-demo.com` |
| Production | `https://api.gusto.com` |

To use the demo environment, pass custom client options:

```ruby
provider :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET'],
  client_options: {
    site: 'https://api.gusto-demo.com',
    authorize_url: '/oauth/authorize',
    token_url: '/oauth/token'
  }
```

## Usage

### Ruby (Rack / Sinatra)

```ruby
# config.ru
require 'omniauth-gusto-oauth2'

use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']
use OmniAuth::Builder do
  provider :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET']
end

# Sinatra app
get '/auth/gusto_oauth2/callback' do
  auth = request.env['omniauth.auth']

  # auth['uid']                    => "admin-uuid-123"
  # auth['info']['email']          => "owner@example.com"
  # auth['info']['name']           => "Jane Doe"
  # auth['info']['company_uuid']   => "company-uuid-456"
  # auth['info']['company_name']   => "Jane's Restaurant"
  # auth['credentials']['token']   => "ACCESS_TOKEN"
  # auth['credentials']['refresh_token'] => "REFRESH_TOKEN"

  "Hello, #{auth['info']['name']}!"
end

get '/auth/failure' do
  "Authentication failed: #{params[:message]}"
end
```

### Rails — Standalone OmniAuth

```ruby
# config/initializers/omniauth.rb
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET']
end
```

```ruby
# config/routes.rb
Rails.application.routes.draw do
  get '/auth/gusto_oauth2/callback', to: 'sessions#create'
  get '/auth/failure', to: 'sessions#failure'
end
```

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def create
    auth = request.env['omniauth.auth']

    account = Account.find_or_initialize_by(provider: auth['provider'], uid: auth['uid'])
    account.update!(
      email: auth['info']['email'],
      name: auth['info']['name'],
      company_uuid: auth['info']['company_uuid'],
      company_name: auth['info']['company_name'],
      access_token: auth['credentials']['token'],
      refresh_token: auth['credentials']['refresh_token'],
      token_expires_at: Time.at(auth['credentials']['expires_at'])
    )

    session[:account_id] = account.id
    redirect_to root_path, notice: "Connected to Gusto as #{account.name}"
  end

  def failure
    redirect_to root_path, alert: "Gusto authentication failed: #{params[:message]}"
  end
end
```

### Rails — With Devise

In `config/initializers/devise.rb`:

```ruby
config.omniauth :gusto_oauth2, ENV['GUSTO_CLIENT_ID'], ENV['GUSTO_CLIENT_SECRET']
```

Add to your routes:

```ruby
devise_for :users, controllers: { omniauth_callbacks: 'users/omniauth_callbacks' }
```

Create the callbacks controller:

```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def gusto_oauth2
    auth = request.env['omniauth.auth']
    @user = User.from_omniauth(auth)

    if @user.persisted?
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: 'Gusto') if is_navigational_format?
    else
      session['devise.gusto_data'] = auth.except(:extra)
      redirect_to new_user_registration_url
    end
  end

  def failure
    redirect_to root_path, alert: "Gusto authentication failed: #{failure_message}"
  end
end
```

```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :database_authenticatable, :omniauthable, omniauth_providers: [:gusto_oauth2]

  def self.from_omniauth(auth)
    where(provider: auth.provider, uid: auth.uid).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.name = auth.info.name
    end
  end
end
```

## Auth Hash

Here's an example of the authentication hash available in `request.env['omniauth.auth']`:

```ruby
{
  "provider" => "gusto_oauth2",
  "uid" => "admin-uuid-abc123",
  "info" => {
    "email" => "owner@example.com",
    "name" => "Jane Doe",
    "first_name" => "Jane",
    "last_name" => "Doe",
    "company_uuid" => "company-uuid-xyz789",
    "company_name" => "Jane's Restaurant"
  },
  "credentials" => {
    "token" => "ACCESS_TOKEN",
    "refresh_token" => "REFRESH_TOKEN",
    "expires_at" => 1704067200,
    "expires" => true
  },
  "extra" => {
    "raw_info" => {
      "uuid" => "admin-uuid-abc123",
      "email" => "owner@example.com",
      "first_name" => "Jane",
      "last_name" => "Doe",
      "name" => "Jane Doe",
      "company_uuid" => "company-uuid-xyz789",
      "company_name" => "Jane's Restaurant"
    }
  }
}
```

## Gusto OAuth2 Specifics

- **REST API**: Gusto uses a REST API. User info is fetched via `GET /v1/me` and token info via `GET /v1/token_info` after token exchange.
- **Auth Scheme**: Gusto requires credentials in the POST body as JSON (`Content-Type: application/json`).
- **Token Expiry**: Access tokens expire after **2 hours**. Refresh tokens **never expire** but are **single-use** — each refresh returns a new refresh token that must be stored.
- **API Versioning**: All requests include an `X-Gusto-API-Version: 2024-04-01` header. Gusto uses date-based API versioning.
- **UID**: The `uid` is the resource owner UUID from `/v1/token_info`. Falls back to the user UUID from `/v1/me` if unavailable.
- **Per-Company Auth**: As of API version `v2023-05-01`, each company must be authorized individually through separate OAuth flows.

## Token Refresh

Gusto access tokens expire after 2 hours. Refresh tokens are **single-use** — always store the new refresh token after each refresh. This gem includes a `TokenClient` for refreshing tokens outside the OmniAuth flow:

```ruby
client = OmniAuth::GustoOauth2::TokenClient.new(
  client_id: ENV['GUSTO_CLIENT_ID'],
  client_secret: ENV['GUSTO_CLIENT_SECRET']
)

result = client.refresh_token(account.refresh_token)

if result.success?
  account.update!(
    access_token: result.access_token,
    refresh_token: result.refresh_token,  # IMPORTANT: always store the new refresh token
    token_expires_at: Time.at(result.expires_at)
  )
else
  Rails.logger.error "Gusto token refresh failed: #{result.error}"
end
```

### Rails — Background Token Refresh Job

```ruby
# app/jobs/gusto_token_refresh_job.rb
class GustoTokenRefreshJob < ApplicationJob
  queue_as :default

  def perform(account_id)
    account = Account.find(account_id)
    client = OmniAuth::GustoOauth2::TokenClient.new(
      client_id: ENV['GUSTO_CLIENT_ID'],
      client_secret: ENV['GUSTO_CLIENT_SECRET']
    )

    return unless client.token_expired?(account.token_expires_at)

    result = client.refresh_token(account.refresh_token)

    if result.success?
      account.update!(
        access_token: result.access_token,
        refresh_token: result.refresh_token,
        token_expires_at: Time.at(result.expires_at)
      )
    else
      Rails.logger.error "[Gusto] Token refresh failed for account #{account_id}: #{result.error}"
    end
  end
end
```

### Check Token Expiration

```ruby
# Check if token is expired (with 5-minute buffer by default)
client.token_expired?(account.token_expires_at)

# Custom buffer (e.g., refresh 10 minutes before expiry)
client.token_expired?(account.token_expires_at, buffer_seconds: 600)
```

### TokenResult Object

| Method | Description |
|--------|-------------|
| `success?` | Returns `true` if refresh succeeded |
| `failure?` | Returns `true` if refresh failed |
| `access_token` | The new access token |
| `refresh_token` | The new refresh token (single-use — always store it) |
| `expires_at` | Unix timestamp when token expires |
| `expires_in` | Seconds until token expires |
| `error` | Error message if failed |
| `raw_response` | Full response hash from Gusto |

## Development

```bash
bundle install
bundle exec rspec       # 40 examples, 0 failures
bundle exec rubocop     # 0 offenses
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/dan1d/omniauth-gusto-oauth2.

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

Copyright (c) 2026 dan1d
