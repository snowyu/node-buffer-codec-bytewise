# Reference: https://github.com/deanlandolt/bytewise
# Differece: encode to string only.
util        = require("abstract-object/lib/util")
Errors      = require('abstract-object/Error')
Codec       = module.exports = require 'buffer-codec'
isString    = util.isString
isNumber    = util.isNumber
isDate      = util.isDate
isRegExp    = util.isRegExp
isArray     = util.isArray
isFunction  = util.isFunction
isObject    = util.isObject
register    = Codec.register
aliases     = Codec.aliases
alias       = Codec.alias
isBuffer    = Buffer.isBuffer

escapeString    = Codec.escapeString
unescapeString  = Codec.unescapeString
InvalidFormatError    = Errors.InvalidFormatError
InvalidArgumentError  = Errors.InvalidArgumentError
NotSupportedError     = Errors.NotSupportedError

#http://ecma262-5.com/ELS5_HTML.htm#Section_8.5
MaxIntValue   = 0x20000000000000 # 9007199254740992 #2**53
MaxIntSize    = 14 # max integer hex string size =MaxIntValue.toString().length 
MaxUInt32 = 0xffffffff
MaxUInt32Count = 0x100000000 #MaxUInt32+1
MaxUInt32Size = 8

# Sort tags used to preserve binary total order
NULL = ' '
NUMBER = 'N'
NEGATIVE_INFINITY = '0'
NUMBER_NEGATIVE_INFINITY = NUMBER + NEGATIVE_INFINITY
# the following char is bytes number.
NEGATIVE = '-' # packed in an inverted form to sort bitwise ascending
POSITIVE = '0'
INTEGER  = 'i' # use hex string to store.
NUMBER_INT = NUMBER + INTEGER
NEGATIVE_INT = NUMBER_INT + NEGATIVE
POSITIVE_INT = NUMBER_INT + POSITIVE
DATE = 'D'
DATE_PRE_EPOCH = DATE + NEGATIVE  # packed identically to a NEGATIVE_NUMBER
DATE_POST_EPOCH = DATE + POSITIVE # packed identically to a POSITIVE_NUMBER
# the following char is bytes number.
FLOAT = 'f'
NUMBER_FLOAT = NUMBER + FLOAT
NEGATIVE_FLOAT = NUMBER_FLOAT + NEGATIVE
POSITIVE_FLOAT = NUMBER_FLOAT + POSITIVE
POSITIVE_INFINITY = '9'
NUMBER_POSITIVE_INFINITY = NUMBER + POSITIVE_INFINITY
BUFFER = 'B'
STRING = '"'
ARRAY = '['  # escapes nested types with bit shifting where necessary to maintain order
OBJECT = '{' # just like couchdb member order is preserved and matters for collation
REGEXP = 'R' # packed as tuple of two strings, the end being flags
FUNCTION = 'f' # packed as array, revived by safe eval in an isolated environment (if available)
FALSE = 'F'
TRUE = 'T'
UNDEFINED = '~'

padChar = (c, len=2) ->
  result = ''
  len++
  while len -= 1
    result += c
  result

#
# * radix:
#   * Optional. An integer between 2 and 36 specifying the base to use for representing numeric values.
toFixedInt = (value, digits=MaxUInt32Size, radix=16)->
  result = padChar 0, digits
  value += MaxUInt32Count if value < 0
  (result+value.toString(radix)).slice(-digits)

intToHex = (num, radix=16)->if (num < 0) then (num+MaxUInt32Count).toString(radix) else num.toString(radix)

class BytewiseCodec
  register BytewiseCodec, Codec
  alias    BytewiseCodec, 'index'
  
  # the configration:
  # for float
  buffer = Codec.getBuffer 8
  decodeFunction = undefined
  bufferEncoding = "hex"
  integerBase    = 16
  baseWidth      = intToHex(MaxUInt32, integerBase).length
  

  ###
  xorNumber = (value)->
    result = ""
    #the value must be less than the MaxIntValue, but xor ...
    x = value ^ MaxUInt32 # xor the js bitwise operation is sign 32bit integer.
    result = intToHex(x) + result
    while (value = (value / MaxUInt32Count) >> 0) > 0
      x = value ^ MaxUInt32 # xor the js bitwise operation is sign 32bit integer.
      result = intToHex(x) + result
    result
  ###
  xorBuffer = (buf, offset=0, end=8)->
    end = buf.length if end > buf.length
    i = offset
    while i < end
      buf[i] = buf[i] ^ 0xff
      i++
    return
    
  encodeInt32 = (value)->
    toFixedInt(value, baseWidth, integerBase)
  encodeDouble = (value)->
    if value >= 0
      buffer.writeDoubleBE value, 0
    else
      buffer.writeDoubleBE -value, 0
      xorBuffer(buffer)
    buffer.toString(bufferEncoding, 0, 8)
  encodeArray = (arr)->
    result = '['
    for item,i in arr
      v = encode(item)
      if i isnt 0
        result += ','
      result += v
    result += ']'
  encodeObject = (obj)->
    result = '{'
    i = 0
    for k,v of obj
      v = encode(v)
      if i isnt 0
        result += ','
      else
        i=1
      result += escapeString(k,"%:,") + ':' + v
    result += '}'

  encode = (data)->
    return UNDEFINED if data is undefined
    return NULL if data is null
    value = if data? and data.valueOf then data.valueOf() else data
    if value isnt value
      throw new InvalidArgumentError('invalid date value') if data instanceof Date
      throw new InvalidArgumentError('NaN value is not permitted')
    return FALSE if value is false
    return TRUE if value is true
    return JSON.stringify(escapeString(value,"%,:")) if isString data

    if isDate data
      #Normalize -0 values to 0
      value = 0 if Object.is(value, -0)
      type = if value < 0 then DATE_PRE_EPOCH else DATE_POST_EPOCH
      #value = (value / 1000) >> 0 # convert to UNIX TimeStamp to get rid of misecond
      return type + encodeDouble(value)
    if isNumber data
      return NUMBER_NEGATIVE_INFINITY if value is Number.NEGATIVE_INFINITY
      return NUMBER_POSITIVE_INFINITY if value is Number.POSITIVE_INFINITY
      #Normalize -0 values to 0
      value = 0 if Object.is(value, -0)
      if value is (value | 0) and Math.abs(value) <= MaxUInt32Count
        type = if value < 0 then NEGATIVE_INT else POSITIVE_INT
        return type + encodeInt32(value)
      else
        type = if value < 0 then NEGATIVE_FLOAT else POSITIVE_FLOAT
        return type + encodeDouble(value)
    return REGEXP + value.toString() if isRegExp data
    return BUFFER + data.toString(bufferEncoding) if isBuffer data
    return encodeArray(value) if isArray data
    return value.toString() if isFunction data
    return encodeObject(value) if isObject(data) and data not instanceof Error
    # TODO Structured Clone algorithm (Blob, File, FileList, Map, Set)
    throw new NotSupportedError('the value type is not supported:' + data)

  decodeRegExp = (str)->
    lastIndex = str.length-1
    if str[lastIndex] != '/'
      lastIndex = str.lastIndexOf '/'
      flags = str.subString lastIndex+1
    pattern = str.subString 1, lastIndex
    new RegExp pattern, flags
  decodeArray = (data)->
    for item in data.split(",")
      decode(item)
  decodeObject = (data)->
    result = {}
    for item in data.split(",")
      [key, value] = item.split(":")
      key = unescapeString(key)
      value = decode(value)
      result[key]=value
    result
  decodeBuffer = (data)->
    buf = new Buffer data.length
    len = buf.write data, 0, bufferEncoding
    buf.slice(0, len)
  decodeNumber = (data)->
    c = data[0]
    data = data.slice(1)
    if c is INTEGER
      decodeInt32(data)
    else if c is FLOAT
      decodeDouble data
    else
      throw new InvalidFormatError("unknown number type flag:", c)
  decodeInt32 = (data)->
    c = data[0]
    data = data.slice(1)
    result = parseInt(data, integerBase)
    if c is NEGATIVE
      return -((result ^ MaxUInt32)+1)
    else if c is POSITIVE
      return result
    else
      throw new InvalidFormatError("unknown sign flag:", c) 
  decodeDouble = (data)->
    c = data[0]
    data = data.slice(1)
    buffer.write data, 0, 8, bufferEncoding
    if c is NEGATIVE
      xorBuffer buffer, 0, 8
      -buffer.readDoubleBE(0)
    else if c is POSITIVE
      buffer.readDoubleBE 0
    else
      throw new InvalidFormatError("unknown sign flag:", c)
  decode = (data)->
    if isString(data) and data.length > 0
      return Number.NEGATIVE_INFINITY if data is NUMBER_NEGATIVE_INFINITY
      return Number.POSITIVE_INFINITY if data is NUMBER_POSITIVE_INFINITY
      switch data[0]
        when STRING     then JSON.parse(unescapeString(data))
        when TRUE       then true
        when FALSE      then false
        when NULL       then null
        when UNDEFINED  then undefined
        when NUMBER     then decodeNumber(data.slice(1))
        when DATE       then new Date(decodeDouble(data.slice(1)))
        when ARRAY      then decodeArray(data.slice(1, data.length-1))
        when OBJECT     then decodeObject(data.slice(1, data.length-1))
        when BUFFER     then decodeBuffer(data.slice(1))
        when REGEXP     then decodeRegExp(data.slice(1))
        when FUNCTION   then (if decodeFunction then decodeFunction(data) else data)
        else
          data
    else
      data
  _encodeString: encode
  _decodeString: decode
  config: (conf)->
    if conf
      decodeFunction = conf.decodeFunction
      bufferEncoding = conf.bufferEncoding if conf.bufferEncoding
      if conf.integerBase >= 2 and conf.integerBase <= 36
        integerBase = conf.integerBase
        baseWidth   = intToHex(MaxUInt32, integerBase).length
      return @
    else
      decodeFunction: decodeFunction
      bufferEncoding: bufferEncoding
      integerBase:    integerBase

