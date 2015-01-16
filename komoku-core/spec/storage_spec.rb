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

    it 'lists keys with last value' do
      @storage.put :foo, 5
      @storage.put :bar, true
      @storage.keys(include: [:value]).should == {'foo' => {type: 'numeric', value: 5}, 'bar' => {type: 'boolean', value:  true}}
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

    it 'returns last value' do
      @storage.put :foo, 1
      @storage.put :foo, 2
      @storage.get(:foo).should == 2
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
      t = t - t.to_i % 60 # we align to minutes so this is to make test always give the same results
      @storage.put :foo, 1, t - 3*60
      @storage.put :foo, 0.5, t - 2*60
      @storage.put :foo, 1.5, t - 1.9*60
      @storage.put :foo, 3, t - 1*60

      data = @storage.fetch :foo, step: '1M'

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

    it 'destroys keys' do
      @storage.put :foo, 1
      @storage.get(:foo).should == 1
      @storage.destroy_key :foo
      @storage.get(:foo).should == nil
      # make sure it also forgets the type
      @storage.put :foo, true
      @storage.get(:foo).should == true
    end
  end

  context 'key opts' do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it 'handles same_value_resolution' do
      # TODO
    end

  end

  context 'type handling' do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it 'handles booleans' do
      @storage.put :foo, true
      @storage.get(:foo).should == true
      @storage.put :bar, false
      @storage.get(:bar).should == false
    end

    it 'doesnt decide key type on empty read' do
      @storage.get :foo
      @storage.put :foo, true
      @storage.get(:foo).should == true
    end

    it 'handles strings' do
      @storage.put :moo, 'whatever'
      @storage.get(:moo).should == 'whatever'
    end

    it 'keeps string  type' do
      @storage.put :foo, 'foo'
      @storage.put :foo, 2
      @storage.get(:foo).should == '2'
    end

    it 'keeps num type' do
      @storage.put :bar, 1
      @storage.put :bar, '2'
      @storage.get(:bar).should == 2
    end

  end

  context 'fetch' do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it "handles 1M resolution" do
      t0 = Time.new 2014, 1, 1
      @storage.put :foo, 1, t0
      @storage.put :foo, 2, t0 + 30
      @storage.put :foo, 3, t0 + 70
      @storage.put :foo, 4, t0 + 100
      @storage.fetch(:foo, step: '1M').should == [[t0, 1.5], [t0+60, 3.5]]
    end

    context "steps" do
      before do
        @base = Komoku::Storage::Engine::Base.new
      end

      it { @base.send(:step, '1M').should == {unit: 'minute', count: 1, span: 60} }
      it { @base.send(:step, '5M').should == {unit: 'minute', count: 5, span: 300} }
      it { @base.send(:step, '2H').should == {unit: 'hour', count: 2, span: 3600*2} }
      it { @base.send(:step, '1m').should include({unit: 'month', count: 1} ) }
    end

    context "boolean" do
      it "10M" do
        t0 = Time.now - Time.now.sec
        @storage.put :foo, true, t0 - 9*60 - 30
        @storage.put :foo, true, t0 - 8*60 - 30
        @storage.put :foo, false, t0 - 8*60 - 20
        @storage.put :foo, true, t0 - 6*60
        @storage.put :foo, true, t0 - 3*60
        @storage.put :foo, false, t0 - 2*60 - 10

        t = @storage.fetch(:foo, since: t0 - 660, step: '1M')
        t.map(&:last).map {|x| x.round(2)}.should == [0, 30, 40, 0, 0, 60, 60, 60, 50, 0, 0].map{|x| (x/60.0).round(2)}
        t[0].first.should == t0 - 600
        t[1].first.should == t0 - 600 + 60
     end
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
      @storage.on_change(:foo) do |key, curr, prev|
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
