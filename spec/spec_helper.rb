require 'komoku/core'
require 'fileutils'
require 'did_you_mean'


tmp_db = "tmp/test.db"
File.unlink tmp_db if File.exists? tmp_db

FileUtils.mkdir_p "tmp"

module TestsHelpers
  def run_websocket_server
    before do
      @server = Komoku::Server::WebsocketServer.start
      sleep 1 # TODO use some hook on server started to avoid sleep
    end

    after do
      Komoku::Server::WebsocketServer.stop
      sleep 0.1 # FIXME no sleep at work
    end
  end

end

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = [:should, :expect]
  end
  config.extend TestsHelpers
end
