require 'spec_helper'
require 'komoku/agent'
require 'faye/websocket'
require 'komoku/server'
require 'benchmark'

$spec_timeout = 1000
Benchmark.bm(20) do |b|

  describe Komoku::Storage do
    before do
      @storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite)
    end

    it " " do
      b.report("put x1000") do
        1000.times do
          @storage.put :foo, rand(1000)
        end
      end

      b.report("get same x1000") do
        1000.times do
          @storage.get :foo
        end
      end
    end

    it " " do
      b.report("put x1000 diff") do
        1000.times do |i|
          @storage.put "key_#{i}", rand(1000)
        end
      end
    end

  end

  describe Komoku::Agent do
    run_websocket_server
    get_agent

    it " " do
      # XXX huge real time but user and system is low, it's not storage,
      # and it shouldn't be network since everything is on localhost, wtf
      b.report("put x100") do
        100.times do
          agent.put :foo, rand(1000)
        end
      end

      b.report("get same x100") do
        100.times do
          agent.get :foo
        end
      end
    end
  end

end

