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
      agent = Komoku::Agent.new server: ws_url
      agent.connect
      agent.get(:foo).should == nil
      agent.get('foo').should == nil
      agent.put(:foo, 239).should == true
      agent.get(:foo).should == 239
    end

    it "should properly return last stored value" do
      agent = Komoku::Agent.new server: ws_url
      agent.connect
      agent.put(:foo, 123).should == true
      agent.put(:foo, 456).should == true
      agent.get(:foo).should == 456
    end
  end

  context "scopes" do
    # TODO run it on something less heavy
    run_websocket_server

    it "keeps scopes separate" do
      agent1 = Komoku::Agent.new server: ws_url
      agent1.connect
      agent2 = Komoku::Agent.new server: ws_url, scope: 's1'
      agent2.connect
      agent3 = Komoku::Agent.new server: ws_url, scope: 's2'
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
      agent = Komoku::Agent.new server: ws_url
      agent.connect
      notified = false
      agent.on_change(:foo) do |key, prev, curr|
        notified = true
        key.should == 'foo'
        prev.should == nil
        curr.should == 2
      end
      agent.put :foo, 2
    end

    it "handles on change from different agent" do
      agent1 = Komoku::Agent.new server: ws_url
      agent2 = Komoku::Agent.new server: ws_url
      agent1.connect
      agent2.connect
      notified = false
      agent1.on_change(:moo) { notified = true }
      agent2.put :moo, 1
      notified.should == true
    end

  end

end
