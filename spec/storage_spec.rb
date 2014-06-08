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
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new
    end

    it 'can read last stored integer' do
      @storage.get(:foo).should == nil
      @storage.put(:foo, 42)
      @storage.get(:foo).should == 42
    end
  end
end
