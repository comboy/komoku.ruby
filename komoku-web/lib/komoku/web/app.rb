#require 'sinatra'
require 'sinatra/base'
require 'json'
require_relative '../../../../komoku-core/lib/komoku/agent'


class MyApp < Sinatra::Application
  set :public_folder, File.dirname(__FILE__) + '/../../../public/'

  agent = Komoku::Agent.new server: 'ws://127.0.0.1:7272/', reconnect: true
  agent.connect

  subs = []

  # Subscribe to all key changes, TODO update once .* are implemented
  agent.keys.each_pair do |key, opts|
    agent.on_change(key) do |key, value|
      subs.each do |out|
        data = {key: key, value: value}
        out << "event: value_change\n\n"
        out << "data: #{data.to_json}\n\n"
      end
    end
  end

  get '/' do
    "helloooo"
    erb :layout
  end

  get '/keys.json' do
    agent.keys(include: [:value]).to_json
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

  get '/subscribe' do
     content_type 'text/event-stream'
    stream(:keep_open) do |out|
      subs << out
      out.callback { subs.delete(out) }
    end
  end

end

MyApp.run!
trap("SIGINT") { EM.stop }
sleep # Thin uses EM started by agent..
