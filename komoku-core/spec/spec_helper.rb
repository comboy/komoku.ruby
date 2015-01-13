require 'komoku/core'
require 'fileutils'
require 'did_you_mean'
require 'timeout'


tmp_db = "tmp/test.db"
File.unlink tmp_db if File.exists? tmp_db

FileUtils.mkdir_p "tmp"


module TestsHelpers

  class WsClient

    attr_reader :connected
    attr_reader :ws

    def initialize
      @connected = false
      @events = Queue.new
      @msgs = Queue.new
      @ws = nil
      @thread = Thread.new do
        EM.run do
          @ws = Faye::WebSocket::Client.new("ws://127.0.0.1:7373/")
          @ws.on :open do |event|
            @connected = true
            @events.push event
          end

          @ws.on :message do |event|
            data = event.data
            @events.push event
            @msgs.push data
          end

          @ws.on :close do |event|
            @connected = false
            @events.push event
          end
        end
      end
      sleep 0.02 # helps with tests hanging randomly sometimes, but why?
    end

    def send(data)
      @ws.send data
    end

    def read
      # TODO add timeout
      @msgs.pop
    end

    def wait_for_event
      @events.pop
    end

    def close
      @ws.close
      @thread.kill
    end
  end


  def start_ws_server(opts = {})
    # Do not like it, But it seems most ruby servers doesn't like to live and die within another ruby process
    args = " --lag #{opts[:lag].to_f}" if opts[:lag]
    @ws_server_pid = Process.spawn("ruby spec/helpers/test_server.rb#{args}")
    #Komoku::Server::WebsocketServer.logger
    sleep 1 # TODO use some hook on server started to avoid sleep
  end

  def stop_ws_server
    Process.kill 9, @ws_server_pid
    Process.waitpid @ws_server_pid
  end

  def run_websocket_server(opts={})
    before do
      start_ws_server(opts)
    end

    after do
      stop_ws_server
    end
  end

  def ws_client
    client = WsClient.new
    client.wait_for_event
    client
  end

  def ws_url
    "ws://127.0.0.1:7373/"
  end

  def get_agent(opts={})
    let :agent do
      agent = Komoku::Agent.new({server: ws_url, async: false}.merge opts)
      agent.connect
      agent
    end
  end

end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
  config.extend TestsHelpers
  config.include TestsHelpers

  # at this point some errors may cause it to hang indefinitely so let's get the backtrace right away
  config.around(:each) do |example|
    Timeout::timeout(10) { example.run }
  end

end
