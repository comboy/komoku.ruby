#require 'sinatra'
require 'sinatra/base'
require 'json'
require_relative '../../../../komoku-core/lib/komoku/agent'


class MyApp < Sinatra::Application
  set :public_folder, File.dirname(__FILE__) + '/../../../public/'
  #set :bind, '0.0.0.0'

  agent = Komoku::Agent.new server: 'ws://127.0.0.1:7272/', reconnect: true
  agent.connect
  agent.logger = Logger.new STDOUT
  agent.logger.level = Logger::DEBUG

  subs = []

  # Subscribe to all key changes, TODO update once .* are implemented
  agent.keys.each_pair do |key, opts|
    agent.on_change(key) do |change|
      subs.each do |out|
        data = {key: change[:key], value: change[:value]}
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
    agent.fetch(params['key'], since: Time.now - 3600*24).to_json # FIXME use limit instead of :since when bool supports it
  end

  get '/graphs.json' do
    {
      'last_hour' => agent.fetch(params['key'], since: Time.now - 3600, step: '1M').map {|x| [x[0].to_i, x[1]]},
      'last_24h' => agent.fetch(params['key'], since: Time.now - 3600*24, step: '1H').map {|x| [x[0].to_i, x[1]]},
      'last_month' => agent.fetch(params['key'], since: Time.now - 3600*24*31, step: '1d').map {|x| [x[0].to_i, x[1]]},
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
