# Komoku::Core

Monitoring and data storage system used for home automation. Complete mess and not working yet, don't even try to dive in.

This is going to be split into separate gems, komoku-core, komoku-agent, komoku-server, but until then keeping everything in one place make development easier.

Designed specificaly for my use case:

* big key value storage with history of the changes
* clients should be able to subscribe to value changes
* easy stats of value changes, e.g. for boolean you should be able to get daily % of true value
* rrd-like behavior for dense time values, but hopefully more configurable
* fast fetching of the last stored value, ok to be slowish with fetching stats

possibly:

* ability to use as a lib for simple time in value storage locally without central server

# Spec draft

Key types:

* numeric
* on/off (boolean)
* string (reperesanting state, version or whatever)

## Installation

Add this line to your application's Gemfile:

    gem 'komoku-core'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install komoku-core

## Usage

nope

