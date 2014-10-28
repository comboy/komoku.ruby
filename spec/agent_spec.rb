require 'spec_helper'
require 'komoku/agent'
require 'faye/websocket'
require 'komoku/server'

describe Komoku::Agent do

  context "connection" do

    run_websocket_server

    it "should connect" do
      agent = Komoku::Agent.new server: "ws://127.0.0.1:7373/"
      agent.connect.should == true
    end
  end

  context "connection failure" do

    # no websocket server running

    it "should fail" do
      expect do
        agent = Komoku::Agent.new server: "ws://127.0.0.1:7373/"
        agent.connect
      end.to raise_error
    end
  end
end
