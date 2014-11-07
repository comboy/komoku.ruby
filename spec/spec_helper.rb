require 'komoku/core'
require 'fileutils'
require 'did_you_mean'


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

  def run_websocket_server
    before do
      @server = Komoku::Server::WebsocketServer.start
      sleep 1 # TODO use some hook on server started to avoid sleep
    end

    after do
      Komoku::Server::WebsocketServer.stop
      sleep 0.1 # FIXME no sleep at work
    end
  end

  def ws_client
    client = WsClient.new
    client.wait_for_event
    client
  end

end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
  config.extend TestsHelpers
  config.include TestsHelpers
end
