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
    get_agent

    it "is able to store data" do
      agent.get(:foo).should == nil
      agent.get('foo').should == nil
      agent.put(:foo, 239).should == true
      agent.get(:foo).should == 239
    end

    it "returns last stored value" do
      agent.put(:foo, 123).should == true
      agent.put(:foo, 456).should == true
      agent.get(:foo).should == 456
    end

    it "handles boolean values" do
      agent.put(:foo, false)
      agent.get(:foo).should == false
    end

    it "handles string values" do
      agent.put(:foo, 'oink')
      agent.get(:foo).should == 'oink'
    end

    it "stores time properly" do
      t = Time.now - 300
      agent.put(:foo, 123, t)
      agent.fetch(:foo)[0].first.should be_kind_of Time
      agent.fetch(:foo)[0].first.to_i.should == t.to_i
    end
  end

  context "lazy get" do
    run_websocket_server
    get_agent

    it "can do something without scope" do
      agent1 = Komoku::Agent.new server: ws_url, async: false
      agent1.connect
      agent1.put :foo, 1
      agent2 = Komoku::Agent.new server: ws_url, async: false
      agent2.connect
      agent2.lazy_get(:foo).should == 1

      agent1.put :foo, 2
      sleep 0.1
      # make sure no query is done
      get_count = agent2.stats[:ops_count][:get]
      agent2.lazy_get(:foo).should == 2
      agent2.stats[:ops_count][:get].should == get_count
    end

    it "receives proper stats" do
      s = agent.stats[:ops_count]
      get_count = s[:get].to_i
      put_count = s[:put].to_i

      agent.put :foo, 3
      agent.put :foo, 4
      3.times { agent.get :foo }

      s = agent.stats[:ops_count]
      s[:put].should == (put_count + 2)
      s[:get].should == (get_count + 3)
    end
  end

  context "fetch data" do
    run_websocket_server
    get_agent

    it "is able to fetch the last value" do
      agent.put(:foo, 123)
      ret = agent.last :foo
      ret[:value].should == 123
    end

    it "is able to fetch the previous value" do
      agent.put(:foo, 3)
      agent.put(:foo, 123)
      agent.put(:foo, 123)
      ret = agent.previous :foo
      ret[:value].should == 3
    end

    it "is able to fetch last values" do
      agent.fetch(:foo).should == []
      agent.put(:foo, 6); agent.put(:foo, 9)
      agent.fetch(:foo).map(&:last).should == [6,9]
    end

    it "lists stored keys" do
      agent.keys.should == {}
      agent.put(:foo, 1)
      agent.put(:bar, 2)
      agent.keys.keys.sort.should == %w{bar foo}
    end

    it "lists stored keys with values" do
      agent.put(:foo, 1)
      agent.put(:bar, false)
      agent.keys(include: [:value]).should == {'foo' => {type: 'numeric', value: 1}, 'bar' => {type: 'boolean', value: false}}
    end

    it "respects :since" do
      agent.put(:foo, 1, Time.now - 2)
      agent.put(:foo, 2)
      data = agent.fetch(:foo, since: Time.now - 1)
      data.size.should == 1
      agent2 = Komoku::Agent.new server: ws_url, scope: 's1', async: false
      agent2.connect
      data[0].last.should == 2
    end

  end
 
  context "define keys" do
    run_websocket_server
    get_agent

    it "defines string key type" do
      ret = agent.define_keys({
        foo: {type: 'string'}
      })
      agent.put :foo, 3
      agent.get(:foo).should == '3'
      # second define with the same type does nothing (no error)
      ret = agent.define_keys({ foo: {type: 'string'} })
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

    it "can do something without scope" do
      agent1 = Komoku::Agent.new server: ws_url, async: false
      agent1.connect
      agent1.put :foo, 1
      agent2 = Komoku::Agent.new server: ws_url, scope: 's1', async: false
      agent2.connect
      agent2.put :foo, 2
      agent1.get(:foo).should == 1

      agent2.put '.foo', 3
      agent1.get(:foo).should == 3
    end
  end

  context "subscriptions" do
    run_websocket_server

    it "handles on change notifications properly" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      notified = false
      cp = nil
      agent.on_change(:foo) do |change|
        cp = change
        notified = true
      end
      agent.put :foo, 2
      sleep 0.2
      notified.should == true
      cp[:key].should == 'foo'
      cp[:value].should == 2
      cp[:time].should be_within(1).of Time.now.to_f
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

    it "provides correct arguments to the block" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      agent.put :foo, 1
      notified = false
      agent.on_change(:foo) do |change|
        change[:key].should == 'foo'
        change[:value].should == 2
        change[:previous_value].should == 1
        notified = true
      end
      agent.put :foo, 2
      sleep 0.2 # some time to receive notification
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

    it "can do get within on_change block" do
      agent = Komoku::Agent.new server: ws_url, async: false
      agent.connect
      notified = false
      agent.put :moo, 7
      moo_get = nil
      agent.on_change(:foo) do
        moo_get = agent.get(:moo)
        notified = true
      end
      agent.put :foo, 123
      sleep 0.2 # some time to receive notification
      notified.should == true
      moo_get.should == 7
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
      agent.disconnect
      stop_ws_server
    end

  end

  context "handling connection problems" do
    it "resubcribes after disconnection" do
      start_ws_server
      agent = Komoku::Agent.new server: ws_url, async: false, reconnect: true
      agent.connect
      notified = false
      agent.on_change(:moo) { notified = true }
      stop_ws_server
      start_ws_server
      sleep 0.5 # give it some time to reconnect
      agent.put :moo, 1
      sleep 0.5 # give it some time to receive notification
      notified.should == true
      agent.disconnect
      stop_ws_server
    end
  end

end
