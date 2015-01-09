# Bytewise Codec [![Build Status](https://img.shields.io/travis/snowyu/node-buffer-codec-bytewise/master.png)](http://travis-ci.org/snowyu/node-buffer-codec-bytewise) [![npm](https://img.shields.io/npm/v/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) [![downloads](https://img.shields.io/npm/dm/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) [![license](https://img.shields.io/npm/l/buffer-codec-bytewise.svg)](https://npmjs.org/package/buffer-codec-bytewise) 


A binary string serialization which sorts bytewise for arbitrarily complex data structures, respecting [bytewise](https://github.com/deanlandolt/bytewise) structured sorting efficiently.

## Purpose

* use readable binary string serialization instead of Buffer.
+ add the integer(int32) serialization when number is integer and less than MaxUInt32.
+ RegExp serialization
+ Configuration: bytewise.config(Configuration)
  * `decodeFunction` *(func)*: function serialization: only config the cfg.decodeFunction to decode the function:
    * bytewise.config({decodeFunction: function(data) {return eval('('+data+')')})
  * `bufferEncoding` *(string)*: the buffer encoding, defaults to 'hex'.
  * `integerBase` *int*: the int32 base. it's in [2,36]. defaults to 16.
  * `getBuffer` *(func)*: get a Buffer instance with specified byte length.
    * function (length, reusable = true)
      * length: the max byte length of the buffer
      * reusable: the buffer is a temp buffer use to convert the value if true
  * `ignoreCircular` *(bool)*: defaults to false, throws exception.
* encode(data, options), the options:
  * `sortObject` *{bool}*: sort by keys, defaults to true
  * `sortArray` *(bool)*: defaults to false.


## Supported Structures

This is the top level order of the various structures that may be encoded:

* `null`: " " serialize to a space char.
* `false`: "F"
* `true`: "T"
* NEGATIVE_INFINITY: "0"
* POSITIVE_INFINITY: "9"
* `String`: JSON.stringify
* `Number`: "N"
  * integer: "i" int32 Hex string if value less than MaxUInt32 else treat as double float.
  * double: "f"
  * negative flag: "-"
  * positive flag: "0"
* `Date`: 'D' double float.
* `Buffer`: "B" hex String
* `Array`: like JSON array, but the element value is bytewise serialization.
* `Object`: like JSON array, but the element value is bytewise serialization.
* `RegExp`: "R" with stringified "/pattern/flags"
* `Function`: "f" with stringified "function(){}"
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
     assert.equal(encode(null), ' ')
      assert.equal(encode(false), 'F')
      assert.equal(encode(true), 'T')
      assert.equal(encode(undefined), '~')

      assert.equal(encode(-Infinity), 'N0')
      assert.equal(encode(Infinity), 'N9')
      # Serialization does not preserve the sign bit, so 0 is indistinguishable from -0
      assert.equal(encode(-0), 'Ni000000000');
      assert.equal(encode(0), 'Ni000000000');
      # Int32 Numbers are stored in 11 bytes -- 2 chars(Ni) for the type tag and 1 char for the sign
      # and lefts is 8 chars hex string.
      assert.equal(encode(12345), 'Ni000003039')
      # Int32 Negative numbers are stored as positive numbers, 
      # but the sign tag is "-" and their bits inverted
      assert.equal(encode(-12345), 'Ni-ffffcfc7')
      #floating point or integer greater than MaxUInt32, are stored as IEEE 754 doubles
      # and the sub type tag is 'f', stored in 20 bytes
      assert.equal(encode(1.2345), 'Nf03ff3c083126e978d')
      assert.equal(encode(-1.2345), 'Nf-c00c3f7ced916872')

      assert.equal(encode(4294967318), 'Nf041f0000001600000')
      assert.equal(encode(-4294967318), 'Nf-be0ffffffe9fffff')


      assert.equal(encode(new Date(2014,1,1)), 'D042743e9073400000')
      assert.equal(encode(new Date(-2014,1,1)), 'D-bd236a1e7c71ffff')

      assert.equal(encode("hi world"), '"hi world"')
      assert.equal(encode(->), 'function () {}')
      fn = (x,y)->[x,y]
      assert.equal(encode(fn), fn.toString())
      assert.equal(encode(new Buffer([1,2,3,4,5,6,7,8])), 'B0102030405060708')
      expected = [12345, 'good:\nhi,u.', new Date(2014,1,1), 1.2345, new Buffer([1,2,3,4,5,6,7,8])]
      assert.equal(encode(expected), '[Ni000003039,"good%3a\\nhi%2cu.",D042743e9073400000,Nf03ff3c083126e978d,B0102030405060708]')
      expected = {
        num:12345,
        str:'good:\nhi,u.',
        date:new Date(2014,1,1),
        float:1.2345,
        buf:new Buffer([1,2,3,4,5,6,7,8])
      }
      assert.equal(encode(expected), '{num:Ni000003039,str:"good%3a\\nhi%2cu.",date:D042743e9073400000,float:Nf03ff3c083126e978d,buf:B0102030405060708}')
```
