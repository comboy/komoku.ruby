require 'spec_helper'
require 'komoku/agent'
require 'faye/websocket'
require 'komoku/server'

describe Komoku::Agent do

  context "connection" do
    run_websocket_server

    it "should connect" do
      agent = Komoku::Agent.new server: ws_url
      agent.connect.should == true
    end
  end

  context "connection failure" do
    # no websocket server running

    it "should fail" do
      expect do
        agent = Komoku::Agent.new server: ws_url
        agent.connect
      end.to raise_error
    end
  end

  context "put and get" do
    run_websocket_server

    it "should be able to store data" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.get(:foo).should == nil
      agent.get('foo').should == nil
      agent.put(:foo, 239).should == true
      agent.get(:foo).should == 239
    end

    it "should properly return last stored value" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.put(:foo, 123).should == true
      agent.put(:foo, 456).should == true
      agent.get(:foo).should == 456
    end

    it "can handle boolean values" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.put(:foo, false)
      agent.get(:foo).should == false
    end

  end

  context "fetch data" do
    run_websocket_server

    it "should be able to fetch last values" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.fetch(:foo).should == []
      agent.put(:foo, 6); agent.put(:foo, 9)
      agent.fetch(:foo).map(&:last).should == [6,9]
    end

    it "should list stored keys" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.keys.should == {}
      agent.put(:foo, 1)
      agent.put(:bar, 2)
      agent.keys.keys.sort.should == %w{bar foo}
    end

    it "should list stored keys with values" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.put(:foo, 1)
      agent.put(:bar, false)
      agent.keys(include: [:value]).should == {'foo' => {type: 'numeric', value: 1}, 'bar' => {type: 'boolean', value: false}}
    end

  end

  context "scopes" do
    # TODO run it on something less heavy
    run_websocket_server

    it "keeps scopes separate" do
      agent1 = Komoku::Agent.new server: ws_url, async: false
      agent1.connect
      agent2 = Komoku::Agent.new server: ws_url, scope: 's1', async: false
      agent2.connect
      agent3 = Komoku::Agent.new server: ws_url, scope: 's2', async: false
      agent3.connect
      agent1.put(:foo, 123)
      agent2.get(:foo).should == nil
      agent2.put(:foo, 2)
      agent2.get(:foo).should == 2
      agent3.get(:foo).should == nil
      agent1.get(:foo).should == 123
    end
  end

  context "subscriptions" do
    run_websocket_server

    it "handles on change notifications properly" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      notified = false
      agent.on_change(:foo) do |key, curr, prev|
        notified = true
        key.should == 'foo'
        prev.should == nil
        curr.should == 2
      end
      agent.put :foo, 2
    end

    it "handles on change from different agent" do
      agent1 = Komoku::Agent.new server: ws_url, async: false
      agent2 = Komoku::Agent.new server: ws_url, async: false
      agent1.connect
      agent2.connect
      notified = false
      agent1.on_change(:moo) { notified = true }
      agent2.put :moo, 1
      sleep 1 # give it some time to receive notification
      notified.should == true
    end


    it "handles exceptions in on change blocks" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      notified = false
      agent.on_change(:foo) do
        notified = true
        raise "boom"
      end
      agent.put :foo, 123
      sleep 0.2 # some time to receive notification
      notified.should == true
      agent.get(:foo).should == 123
    end
  end

  context "async" do

    it "should use fake logger (testing spec helper)" do
      start_ws_server lag: 0.2
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      t0 = Time.now
      agent.put :foo, 1
      (Time.now - t0).should > 0.2
      stop_ws_server
    end

    it "can store data asynchronusly" do
      start_ws_server lag: 0.2
      agent = Komoku::Agent.new server: ws_url
      agent.connect

      t0 = Time.now
      agent.put :foo, 31337
      (Time.now - t0).should < 0.1
      sleep 0.3
      agent.get(:foo).should == 31337
      stop_ws_server
    end

    it "can queue stored values when there is no sever connection" do
      start_ws_server
      agent = Komoku::Agent.new server: ws_url
      agent.put :foo, 1
      agent.put :foo, 2
      agent.connect
      sleep 0.2
      agent.get(:foo).should == 2
      stop_ws_server
    end

    it "can handle disconnection" do
      start_ws_server
      agent = Komoku::Agent.new server: ws_url, reconnect: true
      agent.connect
      agent.put :foo, 1
      stop_ws_server
      start_ws_server
      agent.put :foo, 2
      sleep 0.2
      agent.get(:foo).should == 2
      agent.disconnect
      stop_ws_server
    end

    it "can handle server taking to respond more than timeout" do
      start_ws_server lag: 1
      agent = Komoku::Agent.new server: ws_url, timeout: 0.5, async: true, reconnect: true
      agent.connect
      agent.put :foo, 31337
      sleep 1.5
      stop_ws_server
      start_ws_server # now responding prorperly
      sleep 0.5 # give it some time to reconnect
      agent.get(:foo).should == 31337
      stop_ws_server
    end

  end

end
