chai            = require 'chai'
sinon           = require 'sinon'
sinonChai       = require 'sinon-chai'
should          = chai.should()
expect          = chai.expect
assert          = chai.assert
Codec           = require '../src/bytewise-codec'
Errors          = require 'abstract-object/Error'
util            = require 'abstract-object/util'
inherits        = util.inherits
isFunction      = util.isFunction
setImmediate    = setImmediate || process.nextTick

chai.use(sinonChai)

describe "BytewiseCodec", ->
  codec = Codec('bytewise')
  
  describe ".encode", ->
    encode = codec.encode.bind(codec)
    it "should encode nullable types to a string", ->
      assert.equal(encode(null), ' ')
      assert.equal(encode(false), 'F')
      assert.equal(encode(true), 'T')
      assert.equal(encode(undefined), '~')
    it "should encode number type to a string", ->
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
    it "should encode date type to a string", ->
      assert.equal(encode(new Date("2014-01-31T16:00:00.000Z")), 'D042743e9073400000')
      assert.equal(encode(new Date("-002014-01-31T16:00:00.000Z")), 'D-bd236a1e7c71ffff')
    it "should encode string type to a string", ->
      assert.equal(encode("hi world"), '"hi world"')
      assert.equal(encode("你好"), '"你好"')
    it "should encode function type to a string", ->
      assert.equal(encode(->), 'function () {}')
      fn = (x,y)->[x,y]
      assert.equal(encode(fn), fn.toString())
    it "should encode buffer type to a string", ->
      assert.equal(encode(new Buffer([1,2,3,4,5,6,7,8])), 'B0102030405060708')
    it "should encode array type to a string", ->
      expected = [12345, 'good:\nhi,u.', new Date("2014-01-31T16:00:00.000Z"), 1.2345, new Buffer([1,2,3,4,5,6,7,8])]
      assert.equal encode(expected), '[Ni000003039,"good%3a\\nhi%2cu.",D042743e9073400000,Nf03ff3c083126e978d,B0102030405060708]'
    it "should encode object type to a string", ->
      expected = 
        num:12345
        str:'good:\nhi,u.'
        date:new Date("2014-01-31T16:00:00.000Z")
        float:1.2345
        buf:new Buffer([1,2,3,4,5,6,7,8])
      assert.equal encode(expected), '{num:Ni000003039,str:"good%3a\\nhi%2cu.",date:D042743e9073400000,float:Nf03ff3c083126e978d,buf:B0102030405060708}'
  describe ".decode", ->
    decode = codec.decode.bind(codec)
    it "should return data directly when can not decode", ->
      assert.equal(decode('hisl392wekS'), 'hisl392wekS')
    it "should decode nullable types", ->
      assert.equal(decode(' '), null)
      assert.equal(decode('F'), false)
      assert.equal(decode('T'), true)
      assert.equal(decode('~'), undefined)
    it "should decode number type", ->
      assert.equal(decode('N0'), -Infinity)
      assert.equal(decode('N9'), Infinity)
      assert.equal(decode('Ni000000000'), 0);
      assert.equal(decode('Ni000003039'), 12345)
      assert.equal(decode('Ni-ffffcfc7'), -12345)
      assert.equal(decode('Nf03ff3c083126e978d'), 1.2345)
      assert.equal(decode('Nf-c00c3f7ced916872'), -1.2345)

      assert.equal(decode('Nf041f0000001600000'), 4294967318)
      assert.equal(decode('Nf-be0ffffffe9fffff'), -4294967318)
    it "should decode date type", ->
      assert.deepEqual(decode('D042743e9073400000'), new Date("2014-01-31T16:00:00.000Z"))
      assert.deepEqual(decode('D-bd236a1e7c71ffff'), new Date("-002014-01-31T16:00:00.000Z"))
    it "should decode string type", ->
      assert.equal(decode('"hi world"'), "hi world")
      assert.equal(decode('"你好"'), "你好")
    it "should decode function type", ->
      strfn = 'function (x,y) {return [x,y]}'
      fn = eval("("+strfn+")")
      decodeFunc = (data)-> eval("("+data+")")
      codec.config decodeFunction:decodeFunc
      result = decode(strfn)
      #assert.ok isFunction(result), "should be function"
      assert.typeOf result, 'function'
      assert.equal(result.toString(), fn.toString())
    it "should decode buffer type ", ->
      assert.equal(decode('B0102030405060708').toString(), new Buffer([1,2,3,4,5,6,7,8]).toString())
    it "should decode array type to a string", ->
      expected = [12345, 'good:\nhi,u.', new Date("2014-01-31T16:00:00.000Z"), 1.2345, new Buffer([1,2,3,4,5,6,7,8])]
      assert.deepEqual decode('[Ni000003039,"good%3a\\nhi%2cu.",D042743e9073400000,Nf03ff3c083126e978d,B0102030405060708]'), expected
    it "should decode object type", ->
      expected = 
        num:12345
        str:'good:\nhi,u.'
        date:new Date("2014-01-31T16:00:00.000Z")
        float:1.2345
        buf:new Buffer([1,2,3,4,5,6,7,8])
      assert.deepEqual decode('{num:Ni000003039,str:"good%3a\\nhi%2cu.",date:D042743e9073400000,float:Nf03ff3c083126e978d,buf:B0102030405060708}'), expected

  describe ".config", ->
    it "should set bufferEncoding to base64, and integerBase to 36", ->
      codec.config
        bufferEncoding: 'base64'
        integerBase: 36
      codec.config().should.have.property 'bufferEncoding', 'base64'
      codec.config().should.have.property 'integerBase', 36

    describe ".encode(base64)", ->
      encode = codec.encode.bind(codec)
      it "should encode buffer type to a string", ->
        assert.equal(encode(new Buffer([1,2,3,4,5,6,7,8])), 'BAQIDBAUGBwg=')
      it "should encode int32 type", ->
        assert.equal(encode(12345), 'Ni000009ix')
      it "should encode float type", ->
        assert.equal(encode(1.2345), 'Nf0P/PAgxJul40=')
        assert.equal(encode(4294967318), 'Nf0QfAAAAFgAAA=')
    describe ".decode(base64)", ->
      decode = codec.decode.bind(codec)
      it "should decode buffer type ", ->
        assert.equal(decode('BAQIDBAUGBwg=').toString(), new Buffer([1,2,3,4,5,6,7,8]).toString())
      it "should decode float type", ->
        assert.equal(decode('Nf0P/PAgxJul40='), 1.2345)
        assert.equal(decode('Nf0QfAAAAFgAAA='), 4294967318)
      it "should decode int32 type", ->
        assert.equal(decode('Ni000009ix'), 12345)
