# Komoku protocol

Currently the only implemented handler is websocket (which seems quite suitable). Connection handler is abstracted away from the actual protocol so adding a different transport shouldn't be a problem (e.g. XMPP, TCP or what have you). The main reason for different implementation would probably be bandwidth efficiency. Current websocket protocol is awfully verbose with some redundancy. Even within websocket using protobufs instead of pure json seems like a good idea. Current way of doing things is optimized for simplicity of client implementations.

# Websocket protocol

## General notes

* it is still very likely to change
* communication is assumed to be in conversation form so after you ask for X you should wait for an answer before sending anything new
* there are a few messages that you may receive which are unrelated to current conversation, those will be marked below (e.g. pub)
* all times are represented as float timestamps
* numeric values will arrive as floats, not strings (e.g. {value: 123.4}) so please don't try to run a bank based on this

You should guess it by lack of auth, but it definitely **shouldn not** be currently assumed that untrusted client can connect to komoku. It could spam database, easily ddos and so on.

### Get

    <= {get: {key: 'foo'}}
    => 123

### Put

Put value. With current time:

    <= {put: {key: 'foo', value: 123}}
    => ack

With some time in the past:

    <= {get: {key: 'foo', value: 'yellow', time: 1432468182}}
    => 123

### List keys

List existing keys:

    <= {keys: {}}
    => {foo: {type: 'numeric'}, bar: {type: 'boolean'}}

Along with current values:

    <= {keys: {include: ['value']}}
    => {foo: {type: 'numeric', value: 123}, bar: {type: 'boolean', value: true}}

### Subscribe to key changes

To subscribe:

    <= {sub: {key: 'foo'}}
    => ack

After that, at any point (even during a conversation), you can receive a message like this:

    => {pub: {key: 'foo', value: 234, time: 1432469276, previous_value: 123}}

### Fetch historical values

This API is very very likely to change, current one looks something like this:

    <= {fetch: {key: 'foo', since: 1432469276, step: '6H'}}
    => [[1432469276, 123], [1432490876, 234]]
 

    <= {fetch: {key: 'bar', since: 1432469276, as: 'timespans'}}
    => [[1432469276, 1432469286], [1432490876, 1432492876]]
