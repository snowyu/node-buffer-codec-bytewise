# Bytewise Codec [![Build Status](https://img.shields.io/travis/snowyu/node-buffer-codec-bytewise/master.png)](http://travis-ci.org/snowyu/node-buffer-codec-bytewise) [![npm](https://img.shields.io/npm/v/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) [![downloads](https://img.shields.io/npm/dm/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) [![license](https://img.shields.io/npm/l/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) 


A binary string serialization which sorts bytewise for arbitrarily complex data structures, respecting [bytewise](https://github.com/deanlandolt/bytewise) structured sorting efficiently.

## Purpose

* use readable binary string serialization instead of Buffer.
+ add the integer(int32) serialization when number is integer and less than MaxUInt32.
+ RegExp serialization
+ Configuration: bytewise.config(Configuration)
  + `decodeFunction` *(func)*: function serialization: only config the cfg.decodeFunction to decode the function:
    * bytewise.config({decodeFunction: eval})
  + `bufferEncoding` *(string)*: the buffer encoding, defaults to 'hex'.
  + `integerBase` *int*: the int32 base. it's in [2,36]. defaults to 16.

## Order of Supported Structures

This is the top level order of the various structures that may be encoded:

* `null`: " " serialize to a space char.
* `false`: "F"
* `true`: "T"
* NEGATIVE_INFINITY: "0"
* POSITIVE_INFINITY: "9"
* `Number`: "N"
  * integer: "i" int32 Hex string if value less than MaxUInt32 else treat as double float.
  * double: "f"
  * negative flag: "-"
  * positive flag: "0"
* `Date`: double float.
  * DATE_PRE_EPOCH: '1'
  * DATE_POST_EPOCH: '2' 
* `Buffer`: "B" hex String
* `String`: JSON.stringify
* `Array`: like JSON array, but the element value is bytewise serialization.
* `Object`: like JSON array, but the element value is bytewise serialization.
* `RegExp`: "R" with stringified "/pattern/flags"
* `Function`: "F" with stringified "function(){}"
* `undefined`: "~"


These specific structures can be used to serialize the vast majority of javascript values in a way that can be sorted in an efficient, complete and sensible manner. Each value is prefixed with a type tag(see above), and we do some bit munging to encode our values in such a way as to carefully preserve the desired sort behavior, even in the precense of structural nested.

For example, negative numbers are stored as a different *type* from positive numbers, with its sign bit stripped and its bytes inverted(xor) to ensure numbers with a larger magnitude come first. `Infinity` and `-Infinity` can also be encoded -- they are *nullary* types, encoded using just their type tag. The same can be said of `null` and `undefined`, and the boolean values `false`, `true`. `Date` instances are stored just like `Number` instances -- but as in IndexedDB -- `Date` sorts before `Number` . `Buffer` data can be stored in the raw, and is sorted before `String` data. Then come the collection types -- `Array` and `Object`, along with the additional types defined by es6: `Map` and `Set`. We can even serialize `Function` values and revive them in an isolated [Secure ECMAScript](https://code.google.com/p/es-lab/wiki/SecureEcmaScript) context where they are powerless to do anything but calculate.

## Unsupported Structures

This serialization accomodates a wide range of javascript structures, but it is not exhaustive. Objects or arrays with reference cycles cannot be serialized. `NaN` is also illegal anywhere in a serialized value -- its presense very likely indicates of an error, but more importantly sorting on `NaN` is nonsensical by definition. (Similarly we may want to reject objects which are instances of `Error`.) Invalid `Date` objects are also illegal. Since `WeakMap` and `WeakSet` objects cannot be enumerated they are impossible to serialize. Attempts to serialize any values which include these structures should throw a `TypeError`.


## Usage

The bytewise is registered to [buffer-codec](https://github.com/snowyu/node-buffer-codec).

`bytewise`.`encode` serializes any supported type and returns a buffer, or throws if an unsupported structure is passed:

```js

var Codec = require("buffer-codec-bytewise")
var bytewise = Codec("bytewise")
var assert = require('assert');

// Helper to encode
function encode(value) { return bytewise.encode(value) }

  // Many types can be respresented using only their type tag, a single byte
  // WARNING type tags are subject to change for the time being!
  assert.equal(encode(null), ' ');
  assert.equal(encode(false), 'F');
  assert.equal(encode(true), 'T');
  assert.equal(encode(undefined), '~');

  // Numbers are stored in 9 bytes -- 1 byte for the type tag and an 8 byte float
  assert.equal(encode(12345, 'hex'), '4240c81c8000000000');
  // Negative numbers are stored as positive numbers, but with a lower type tag and their bits inverted
  assert.equal(encode(-12345, 'hex'), '41bf37e37fffffffff');

  // All numbers, integer or floating point, are stored as IEEE 754 doubles
  assert.equal(encode(1.2345, 'hex'), '423ff3c083126e978d');
  assert.equal(encode(-1.2345, 'hex'), '41c00c3f7ced916872');

  // Serialization does not preserve the sign bit, so 0 is indistinguishable from -0
  assert.equal(encode(-0, 'hex'), '420000000000000000');
  assert.equal(encode(0, 'hex'), '420000000000000000');

  // We can even serialize Infinity and -Infinity, though we just use their type tag
  assert.equal(encode(-Infinity, 'hex'), '40');
  assert.equal(encode(Infinity, 'hex'), '43');

  // Dates are stored just like numbers, but with different (and higher) type tags
  assert.equal(encode(new Date(-12345), 'hex'), '51bf37e37fffffffff');
  assert.equal(encode(new Date(12345), 'hex'), '5240c81c8000000000');

  // Strings are encoded as utf8, prefixed with their type tag (0x70, or the "p" character)
  assert.equal(encode('foo'), 'pfoo');
  assert.equal(encode('föo'), 'pfÃ¶o');

  // Buffers are also left alone, other than being prefixed with their type tag (0x60)
  assert.equal(encode(new Buffer('ff00fe01', 'hex'), 'hex'), '60ff00fe01');

  // Arrays are just a series of values terminated with a null byte
  assert.equal(encode([ true, -1.2345 ], 'hex'), 'a02141c00c3f7ced91687200');

  // Strings are also legible when embedded in complex structures like arrays
  // Items in arrays are deliminted by null bytes, and a final end byte marks the end of the array
  assert.equal(encode([ 'foo' ]), '\xa0pfoo\x00\x00');

  // The 0x01 and 0xfe bytes are used to escape high and low bytes while preserving the correct collation
  assert.equal(encode([ new Buffer('ff00fe01', 'hex') ], 'hex'), 'a060fefe0101fefd01020000');

  // Complex types like arrays can be arbitrarily nested, and fixed-sized types don't require a terminating byte
  assert.equal(encode([ [ 'foo', true ], 'bar' ]), '\xa0\xa0\pfoo\x00\x21\x00\pbar\x00\x00');

  // Objects are just string-keyed maps, stored like arrays: [ k1, v1, k2, v2, ... ]
  assert.equal(encode({ foo: true, bar: 'baz' }), '\xb0pfoo\x00\x21\pbar\x00\pbaz\x00\x00');




```
