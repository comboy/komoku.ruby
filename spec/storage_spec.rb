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
      @storage.keys.should == []
      @storage.put :foo, 1
      @storage.keys.should == %w{foo}
      @storage.put :bar, 2
      @storage.keys.should == %w{bar foo}
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

  end
end
