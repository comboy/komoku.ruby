#require 'sinatra'
require 'sinatra/base'
require 'json'
require_relative '../../../../komoku-core/lib/komoku/agent'


class MyApp < Sinatra::Application
  set :public_folder, File.dirname(__FILE__) + '/../../../public/'

  agent = Komoku::Agent.new server: 'ws://127.0.0.1:7272/', reconnect: true
  agent.connect

  get '/' do
    "helloooo"
    erb :layout
  end

  get '/keys.json' do
    agent.keys.to_json
  end

  get '/last.json' do
    agent.fetch(params['key']).to_json
  end

end

MyApp.run!
trap("SIGINT") { EM.stop }
sleep # Thin uses EM started by agent..
