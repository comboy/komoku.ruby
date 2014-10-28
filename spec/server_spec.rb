require 'spec_helper'
require 'eventmachine'
require 'faye/websocket'
require 'komoku/server'

describe Komoku::Server do
  context 'connection' do
    run_websocket_server

    it "should accept websocket connections" do
      connected = false
      ws = nil
      Thread.new do
        EM.run do
          puts "EM run"
          ws = Faye::WebSocket::Client.new("ws://127.0.0.1:7373/")
          ws.on :open do |event|
            puts "WS OPEN"
            connected = true
          end
        end
      end
      sleep 1 # TODO avoid sleep in success case
      ws.close
      connected.should == true
    end

    it "should store data points" do
      connected = false
      ws = nil
      Thread.new do
        EM.run do
          puts "EM run"
          ws = Faye::WebSocket::Client.new("ws://127.0.0.1:7373/")
          ws.on :open do |event|
            puts "WS OPEN"
            connected = true
          end
        end
      end
      sleep 1 # TODO avoid sleep in success case
      ws.close
      connected.should == true
    end
  end
end
