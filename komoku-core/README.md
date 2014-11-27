# Komoku core, storage, server and agent

Start with ../README.md

Below there are components that are supposed to end up as different gems, with most important files to peek in.

I'm trying to keep a full test coverage, focusing more on acceptance than unit tests.

## Core

Components common to everything else that is going to be split into gems.

## Storage

Storage is the key thing, the brain. It handles data storage, fetching and notifications.

Storage can be imlpmented using different engines. Currently I'm only working on <tt>database</tt> with maybe occasional touch of <tt>memory</tt> (which may be dropped because why not just sqlite in memory).

Storage is separated into datasets (which I completely ignore for now not needing them, but I felt like this abstraction layer is useful). You cannot compare values between datasets, but they should also not influnce performance of each other. Basically different databases.

Important non-intuitive - storage is not like an ORM. You shouldn't have two separate instances of storages using the same db, you wouldn't get proper notifications and caching may fail.

* [lib/komoku/storage/engine/database.rb](lib/komoku/storage/engine/database.rb)

## Server

Server provides interface for storage that agents can connect to. Current implementation uses websocket. There is no auth, no wss.

relevant:

* [lib/komoku/server/handler.rb](lib/komoku/server/handler.rb)
* [lib/komoku/server/websocket_server.rb](lib/komoku/server/websocket_server.rb)

## Agent

That's what you use to use komoku. It lives somewhere and pushes data to the server. It can also fetch data and subscribe to changes.

In standalone mode (nod yet present) it should also be able to use storage directly instead of talking to server.

* [lib/komoku/agent.rb](lib/komoku/agent.rb)

# Play

Create a tmp dir, then some server.rb

```
require_relative '../lib/komoku/server'
storage = Komoku::Storage.new engine: Komoku::Storage::Engine::Database.new(db: Sequel.sqlite('local.db'))
Komoku::Server::WebsocketServer.logger = Logger.new STDOUT
Komoku::Server::WebsocketServer.start port: 7272, storage: storage
sleep
```

and then using irb or some agent.rb in the same dir

```
require_relative '../lib/komoku/agent'
require 'pp'

agent = Komoku::Agent.new server: 'ws://10.7.0.10:7272/'
agent.logger = Logger.new STDOUT
aggent.connect

agent.put :foo, 123
puts agent.get :foo
```

You will get better idea what can be done by looking in [spec/agent_spec.rb](spec/agent_spec.rb)

## Any feedback is welcome

Open issues, ask questions, tell me I suck at coding, feedback is good. 
