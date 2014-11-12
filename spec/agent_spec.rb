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

    it "should be a ble to store data" do
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

end
