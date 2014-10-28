require 'pp'
require_relative 'storage'
require_relative 'server/handler'
require_relative 'server/websocket_server'

module Komoku
  class Server

     def initialize
       # TEMP FIXME
       $logger = Logger.new STDOUT
     end

   end
end
