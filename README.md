## Deprecated. I already rewrote most of it to elixir. Check https://github.com/comboy/komoku . Ruby client is still compatible with the new server. 

---

This is not a ready-to-use project. Everything is changing, I don't care about API, I do not version it.

This repo is to be separated into different gems, it's just quicker for now to have everything in one place.

# Komoku

Komoku is a library that I've been missing and a main data storage for my home automation. I also use it (older version, this one is not capable yet) for monitoring services and gathering stats from my servers.

Designed specificaly for my use case. If it fits you we can work together to shape it differently, but right now I'm focusing on me. Here's what I need:

* key value data storage with history of changes
* keys may be of different types and depending on type I want to be able to gather different stats about them
* quick fetching of the last value, stats may be slow
* rrd-like behavior but more configurable, I don't want to worry about millions of records even if I'm pushing many values every 5 seconds
* should work with central storage with agent ability to queue values when server is not available
* all values should be pushed and available to subscribe to in realtime
* as mentioned, agents may subscribe to specific keys values changes, classical pub/sub considered, not sure if needed
* should be also able to work as a self contained solution, without central storage, with as little deps as possible (using say sqlite)

## Data types

So I currently decided to go with 3 data types:

### Numeric

Double. I'm considering using actual numeric type (specified precision, exact). Currently there's only gauge but I plan adding different types similar to what's known from rrdtool. It should be able to use different aggregations (for now, most of my cases are covered with gauge avg/min/max so I'm focusing on that)

HA: tracking temp, humidity light etc.

### Boolean

True and false. But. It represents the state changes that last. So with boolean you should be able to get stats like:

* what value was present at given time
* uptime-like stats e.g. 99.5% true during last month
* sum of time stats e.g. number of hours per day for which the state was false
* maybe common timespans stats (like avg distribution per hour during last month)

So boolean is to me more like representing timespans between value changes.

HA: state of the light somewhere, is door open, is window open

### String

Custom string. A bit too much to describe my use case, but basically you can assign any custom string.

* so you can disable compacting and just use it as a log (better yet let's compact it, keeping in mind that it is a logfile)
* or you can be only assigning to it some set of strings representing state of something (stats then are boolean-alike but with more values)

HA: log, what's the alarm state (armed, disabled, waiting), what room I'm in

## Directories

* komoku-core is the juice and more info in readme inside
* komoku-web is just a messy not really working yet tool to browse the database

## Current dev

I try to make it modular, but currently focusing on sqlite and postgresql as storage layers, websocket used for communication.

Evething in ruby is covered with tests which should also give you an idea what's implemented already. More details in komoku-core/README.md

## Contributing

Really? If you got this far in readme I'm impressed. If this kind of lib is relevant to your interest, let me know.

If you think that I'm reinventing the wheel because there's some tool that covers this, then **please do let me know**. 

Any feedback much appreciated. MIT.

## Author

Kacper Cieśla (comboy)
