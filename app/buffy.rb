require 'sinatra/base'
require 'sinatra/config_file'
require_relative 'sinatra_ext/github_webhook_filter'
require_relative 'lib/responders_loader'

class Buffy < Sinatra::Base
  include RespondersLoader
  register Sinatra::ConfigFile
  register GitHubWebhookFilter

  config_file "../config/settings-#{settings.environment}.yml"

  set :root, File.dirname(__FILE__)

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
    branch = params[:branch].empty? ? nil : params[:branch]
    if params[:journal] == 'Summary PDF'
      #job_id = PaperPreviewWorker.perform_async(params[:repository], params[:journal], branch, sha)
      redirect "/moved"
    elsif params[:journal] == 'Reproducible Preprint'
      job_id = NeurolibreBookBuildTestWorker.perform_async(params[:repository], branch, params[:email])
      erb: submitted
    end
  end

end
