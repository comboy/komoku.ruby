require 'spec_helper'

describe Komoku::Storage do
  context 'memory storage' do

    before do
      @storage = Komoku::Storage.new
    end

    it 'can read last stored integer' do
      @storage.get(:foo).should == nil
      @storage.put(:foo, 42)
      @storage.get(:foo).should == 42
    end
  end

  context 'db storage' do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it 'can read last stored integer' do
      @storage.get(:foo).should == nil
      @storage.put(:foo, 42)
      @storage.get(:foo).should == 42
    end

    it 'lists keys' do
      @storage.keys.should == {}
      @storage.put :foo, 1
      @storage.keys.keys.should == %w{foo}
      @storage.keys['foo'][:type].should == 'numeric'
      @storage.put :bar, 2
      @storage.keys.keys.sort.should == %w{bar foo}
    end

    it 'can fetch data' do
      @storage.put :foo, 1
      @storage.put :foo, 2
      @storage.put :foo, 3

      data = @storage.fetch :foo
      data.map(&:last).should == [1,2,3]
      now = Time.now
      data.map(&:first).each do |time|
        time.should > now - 2
        time.should < now
      end
    end

    it 'returns proper data when using :since' do
      @storage.put :foo, 1, Time.now - 7*60
      @storage.put :foo, 2, Time.now - 4*60
      @storage.put :foo, 3, Time.now - 3*60

      data = @storage.fetch :foo, since: Time.now - 5*60

      data.map(&:last).should == [2,3]
    end

    it 'aggregates values' do
      t = Time.now
      @storage.put :foo, 1, t - 3*60
      @storage.put :foo, 0.5, t - 2*60 
      @storage.put :foo, 1.5, t - 2.1*60
      @storage.put :foo, 3, t - 1*60

      data = @storage.fetch :foo, resolution: '1m'

      data.map(&:last).should == [1,1,3]
    end

    it 'shows stats' do
      @storage.put :foo, 1
      @storage.put :foo, 2
      @storage.put :bar, 3

      stats = @storage.stats
      stats[:keys_count].should == 2
      stats[:data_points_count].should == 3
    end
  end

  context "change notifications" do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it "notifies on key change" do
      @storage.put :foo, 1
      notified = false
      @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 2
      notified.should == true
    end

    it "notifies multiple times" do
      @storage.put :foo, 1
      notified = false
      @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 2
      notified.should == true
      notified = false
      @storage.put :foo, 3
      notified.should == true
    end

    it "notifies on key change on first insert" do
      notified = false
      @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 2
      notified.should == true
    end

    it "doesn't notify if no value change" do
      @storage.put :foo, 1
      notified = false
      @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 1
      notified.should == false
    end

    it "doesn't notify when new value is older" do
      @storage.put :foo, 1
      notified = false
      @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 2, Time.now - 1
      notified.should == false
    end

    it "provides correct arguments in the notification" do
      @storage.put :foo, 1
      notified = false
      @storage.on_change(:foo) do |key, prev, curr|
        key.should == 'foo'
        prev.should == 1
        curr.should == 2
        notified = true
      end
      @storage.put :foo, 2
      notified.should == true
    end

    it "unsubscribes properly" do
      notified = false
      subscription = @storage.on_change(:foo) { notified = true }
      @storage.put :foo, 2
      notified.should == true
      notified = false
      @storage.unsubscribe subscription
      @storage.put :foo, 3
      notified.should == false
    end

  end
end
