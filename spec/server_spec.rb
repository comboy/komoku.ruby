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

    it "should handle on_change subscription" do
      wsc = ws_client
      wsc.send({sub: {key: 'foo'}}.to_json)
      wsc.send({put: {key: 'foo', value: 1}}.to_json)
      msgs = Array.new(2) { JSON.load(wsc.read) }
      msgs.include?('ack').should == true
      msgs.include?({'pub' => {'key' => 'foo', 'prev' => nil, 'curr' => 1}}).should == true
    end

    #TODO should handle incorrect msg somehow
  end
end
