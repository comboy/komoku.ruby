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

    it "should clean subscription after client disconnects" do
      wsc = ws_client
      wsc2 = ws_client
      wsc.send({sub: {key: 'foo'}}.to_json)
      wsc.read # ack
      wsc2.send({stats: {}}.to_json)
      stats = JSON.load(wsc2.read)
      stats['change_notifications_count'].should == 1
      wsc.close
      sleep 0.1
      wsc2.send({stats: {}}.to_json)
      stats = JSON.load(wsc2.read)
      stats['change_notifications_count'].should == 0
    end

    #TODO should handle incorrect msg somehow
  end

  context "handler" do
    it "converts time objs to_i" do
      h = Komoku::Server::Handler.new
      t = Time.now

      x = {foo: 'bar', time: t}
      h.__send__(:convert_time_to_i, x).should == {foo: 'bar', time: t.to_i}

      x = [1,2,{a: [3, {b: t}]}]
      h.__send__(:convert_time_to_i, x).should == [1,2,{a: [3, {b: t.to_i}]}]
    end
  end
end
