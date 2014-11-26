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

  get '/graphs.json' do
    {
      'last_hour' => agent.fetch(params['key'], since: Time.now - 3600, step: '10S'),
      'last_24h' => agent.fetch(params['key'], since: Time.now - 3600*24, step: '5M'),
      'last_month' => agent.fetch(params['key'], since: Time.now - 3600*24*31, step: '6H')
    }.to_json
  end

end

MyApp.run!
trap("SIGINT") { EM.stop }
sleep # Thin uses EM started by agent..
