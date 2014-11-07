require 'spec_helper'
require 'eventmachine'
require 'faye/websocket'
require 'komoku/server'

describe Komoku::Server do
  context 'connection' do
    run_websocket_server

    it "should accept websocket connections" do
      wsc = ws_client
      wsc.connected.should == true
      wsc.close
    end

    it "should store data points" do
      wsc = ws_client

      wsc.send({put: {key: 'foo', value: 324}}.to_json)
      ret = wsc.read
      JSON.load(ret).should == 'ack'

      wsc.send({get: {key: 'foo'}}.to_json)
      ret = wsc.read
      JSON.load(ret).should == 324
    end

    it "should handle incorrect msgs" do
      wsc = ws_client
      wsc.send("doesn't look like a json")
      ret = wsc.read
    end

    #TODO should handle incorrect msg somehow
  end
end
