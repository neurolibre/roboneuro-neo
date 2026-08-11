require 'sinatra/base'
require 'sinatra/config_file'
require_relative 'sinatra_ext/github_webhook_filter'
require_relative 'lib/responders_loader'
require_relative 'coar_notify/coar_notify'
require_relative 'coar_notify/routes/inbox'
require_relative 'coar_notify/routes/inbox_ui'  # Dashboard UI
require_relative 'coar_notify/routes/outbox'

class Buffy < Sinatra::Base
  include RespondersLoader
  register Sinatra::ConfigFile
  register GitHubWebhookFilter

  config_file "../config/settings-#{settings.environment}.yml"

  set :root, File.dirname(__FILE__)

  # Initialize COAR Notify if enabled
  configure do
    CoarNotify.init! if CoarNotify.enabled?
  end

  # Mount COAR Notify routes. Each app scopes its own before filters to its
  # own path prefix, so these pass through untouched for every other request.
  use CoarNotify::Routes::Inbox
  use CoarNotify::Routes::Dashboard
  use CoarNotify::Routes::Outbox

  post '/dispatch' do
    responders.respond(@message, @context)
    halt 200, "Message processed"
  end

  get '/status' do
    "#{settings.buffy[:env][:bot_github_user]} in #{settings.environment}: up and running!"
  end

  get '/' do
    erb :neurolibre
  end

  post '/neurolibre' do
    sha = SecureRandom.hex
    branch = params[:branch]
    repo =  params[:repository]
    email = params[:email]
    executable = params[:journal]
    job_id = NeurolibreBookBuildTestWorker.perform_async(repo, branch, email, executable)
    erb :submitted
  end

end
