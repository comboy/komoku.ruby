require 'spec_helper'
require 'eventmachine'
require 'faye/websocket'
require 'komoku/server'

describe Komoku::Server do
  context 'connection' do
    run_websocket_server

    it "accepts websocket connections" do
      wsc = ws_client
      wsc.connected.should == true
      wsc.close
    end

    it "stores data points" do
      wsc = ws_client

      wsc.send({put: {key: 'foo', value: 324}}.to_json)
      ret = wsc.read
      JSON.load(ret).should == 'ack'

      wsc.send({get: {key: 'foo'}}.to_json)
      ret = wsc.read
      JSON.load(ret).should == 324
    end

    it "handles incorrect msgs" do
      wsc = ws_client
      wsc.send("doesn't look like a json")
      ret = wsc.read
    end

    it "andles on_change subscription" do
      wsc = ws_client
      wsc.send({sub: {key: 'foo'}}.to_json)
      wsc.send({put: {key: 'foo', value: 1}}.to_json)
      msgs = Array.new(3) { JSON.load(wsc.read) }
      msgs[0].should == 'ack'
      msgs[1].should == 'ack'
      msgs[2]['pub'].should include({'key' => 'foo', 'previous_value' => nil, 'value' => 1})
    end

    it "cleans subscription after client disconnects" do
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

    it "handles multiple commands in an array" do
      wsc = ws_client

      wsc.send([
        {put: {key: 'foo', value: 123}},
        {put: {key: 'bar', value: 321}}].to_json)

      ret = wsc.read
      JSON.load(ret).should == %w{ack ack}

      wsc.send([
        {get: {key: 'foo'}},
        {get: {key: 'bar'}}].to_json)
      JSON.load(wsc.read).should == [123, 321]
    end

  end

  context "handler" do
    it "converts time objs to_f" do
      h = Komoku::Server::Handler.new
      t = Time.now

      x = {foo: 'bar', time: t}
      h.__send__(:convert_time_to_f, x).should == {foo: 'bar', time: t.to_f}

      x = [1,2,{a: [3, {b: t}]}]
      h.__send__(:convert_time_to_f, x).should == [1,2,{a: [3, {b: t.to_f}]}]
    end
  end
end
