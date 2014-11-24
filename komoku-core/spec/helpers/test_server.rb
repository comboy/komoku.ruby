require_relative '../../lib/komoku/server'
require 'fileutils'

class FakeSlowLogger
  def initialize(lag = 1)
    @lag = lag
  end

  def method_missing(name, *args)
    sleep @lag
    return true
  end
end

kdir = "#{File.dirname(__FILE__)}/../../"


FileUtils.mkdir_p "#{kdir}/tmp"

pidfile = "#{kdir}/tmp/test_server.pid"

# if previous one survived kill it now
if File.exists?(pidfile)
  oldpid = File.read(pidfile).to_i
  if oldpid != 0
    begin
      Process.kill 9, oldpid
      puts "Goodbye Mr. Bond"
      sleep 0.1
    rescue
    end
  end
end

File.open(pidfile,'w') {|f| f.print Process.pid }


require 'optparse'

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on("--lag N", Float, "force slowdown") do |v|
    options[:lag] = v
  end
end.parse!

Komoku::Server::WebsocketServer.logger = FakeSlowLogger.new options[:lag] if options[:lag]
Komoku::Server::WebsocketServer.start options
sleep
