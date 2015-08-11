'use-strict'
global = exports ? this
# Includes Backbone & Underscore if the environment is NodeJS
_         = (unless typeof exports is 'undefined' then require 'lodash' else global)._
Backbone  = unless typeof exports is 'undefined' then require 'backbone' else global.Backbone
Fun = global.Fun = {}
#### getFunctionName(fun)
# Attempts to safely determine name of a named function returns null if undefined
Fun.getFunctionName = (fun)->
  if (n = fun.toString().match /function+\s{1,}([a-zA-Z_0-9]*)/)? then n[1] else null
#### getConstructorName(fun)
# Attempts to safely determine name of the Class Constructor returns null if undefined
Fun.getConstructorName = (fun)->
  fun.constructor.name || if (name = @getFunctionName fun.constructor)? then name else null
WebSock = global.WebSock ?= {}
class WebSock.Client
  __streamHandlers:{}
  constructor:(@__addr, @__options={})->
    _.extend @, Backbone.Events
    @model = WebSock.SockData 
    @connect() unless @__options.auto_connect? and @__options.auto_connect is false
  connect:->
    validationModel = Backbone.Model.extend
      defaults:
        header:
          sender_id: String
          type: String
          sntTime: Date
          srvTime: Date
          rcvTime: Date
          size: Number
        body:null
      validate:(o)->
        o ?= @attributes
        return "required part 'header' was not defined" unless o.header?
        for key in @defaults.header
          return "required header #{key} was not defined" unless o.header[key]?
        return "wrong value for sender_id header" unless typeof o.header.sender_id is 'string'
        return "wrong value for type header" unless typeof o.header.type is 'string'
        return "wrong value for sntTime header" unless (new Date o.header.sntTime).getTime() is o.header.sntTime
        return "wrong value for srvTime header" unless (new Date o.header.srvTime).getTime() is o.header.srvTime
        return "wrong value for rcvTime header" unless (new Date o.header.rcvTime).getTime() is o.header.rcvTime
        return "required part 'body' was not defined" unless o.body
        return "content size was invalid" unless JSON.stringify o.body is o.size
        return
    opts =
      multiplex: true
      reconnection: true
      reconnectionDelay: 1000
      reconnectionDelayMax: 5000
      timeout: 20000
    _.extend opts, _.pick( @__options, _.keys opts )
    @socket = io "#{@__addr}", opts
    .on 'ws:datagram', (data)=>
      data.header.rcvTime = Date.now()
      (dM = new validationModel).set data
      stream.add dM.attributes if dM.isValid() and (stream = @__streamHandlers[dM.attributes.header.type])?
    .on 'connect', =>
      WebSock.SockData.__connection__ = @
      @trigger 'connect', @
    .on 'disconnect', =>
      @trigger 'disconnect'
    .on 'reconnect', =>
      @trigger 'reconnect'
    .on 'reconnecting', =>
      @trigger 'reconnecting', @
    .on 'reconnect_attempt', =>
      @trigger 'reconnect_attempt', @
    .on 'reconnect_error', =>
      @trigger 'reconnect_error', @
    .on 'reconnect_failed', =>
      @trigger 'reconnect_failed', @
    .on 'error', =>
      @trigger 'error', @
    @
  addStream:(name,clazz)->
    return s if (s = @__streamHandlers[name])?
    @__streamHandlers[name] = clazz
  removeStream:(name)->
    return null unless @__streamHandlers[name]?
    delete @__streamHandlers[name]
  getClientId:->
    return null unless @socket?.io?.engine?
    @socket.io.engine.id
class WebSock.SockData extends Backbone.Model
  header:{}
  initialize:(attributes, options)->
    @__type = Fun.getConstructorName @
    SockData.__super__.initialize.call @, attributes, options
  sync: (mtd, mdl, opt={}) ->
    m = {}
    _.extend @header, opt.header if opt.header?
    # Create-operations get routed to Socket.io
    if mtd == 'create'
      # apply Class Name as type if not set by user
      @header.type ?= @__type
      m.header  = _.extend @header, sntTime: Date.now()
      m.body    = mdl.attributes
      SockData.__connection__.socket.emit 'ws:datagram', m
  getSenderId:->
    @header.sender_id || null
  getSentTime:->
    @header.sntTime || null
  getServedTime:->
    @header.srvTime || null
  getRecievedTime:->
    @header.rcvTime || null
  getSize:->
    @header.size || null
  setRoomId:(id)->
    @header.room_id = id
  getRoomId:->
    @header.room_id
  parse: (data)->
    @header = Object.freeze data.header
    SockData.__super__.parse.call data.body
class WebSock.Message extends WebSock.SockData
  defaults:
    text:""
class WebSock.RoomMessage extends WebSock.SockData
  defaults:
    room_id:null
    status:"pending"
  validate:(o)->
    return "parameter 'room_id' must be set" unless o.room_id? or @attributes.room_id
  initialize:(attrs,options={})->
    @header.room_id = options.room_id if options.room_id?
    RoomMessage.__super__.initialize.apply @, arguments
class WebSock.CreateRoom extends WebSock.RoomMessage
class WebSock.ListRooms extends WebSock.SockData
  defaults:
    rooms:[]
class WebSock.JoinRoom extends WebSock.RoomMessage
  set:(attrs,opts)->
    if attrs.room_id?
      @header.room_id = attrs.room_id
    JoinRoom.__super__.set.call @, attrs, opts
  sync:(mtd,mdl,opts)->
    delete mdl.body
    JoinRoom.__super__.sync.call @, mtd, mdl, opts
class WebSock.LeaveRoom extends WebSock.RoomMessage
class WebSock.StreamCollection extends Backbone.Collection
  model:WebSock.SockData
  fetch:->
    # not implemented
    return false
  sync:()-> 
    # not implemented
    return false
  _prepareModel: (attrs,options)->
    if attrs instanceof Backbone.Model
      attrs.collection = @ unless attrs.collection
      return attrs
    options = if options then _.clone options else {}
    options.collection = @
    model = new @model attrs.body, options
    model.header = Object.freeze attrs.header
    return model unless model.validationError
    @trigger 'invalid', @, model.validationError, options
    false
  send:(data)->
    @create data
  initialize:->
    _client = arguments[0] if arguments[0] instanceof WebSock.Client
if module?.exports?.WebSock?
  module.exports.init = (app, listeners=[])->
    server  = require('http').Server app
    io      = require('socket.io') server 
    redis   = require 'socket.io-redis'
    io.adapter redis {host: 'localhost', port: 6379}
    io.sockets.on 'connect', (client)=>
      client.on 'ws:datagram', (data)->
        data.header.srvTime   = Date.now()
        data.header.sender_id = client.id
        if data.header.type is 'ListRooms'
          data.body.status = 'success'
          data.body.rooms = _.keys io.sockets.adapter.rooms
          client.emit 'ws:datagram', data
          return
        if data.header.type is 'CreateRoom'
          unless 0 <= (_.keys io.sockets.adapter.rooms).indexOf data.body.room_id
            data.body.status = 'success'
            client.join data.body.room_id
          else
            data.body.status = 'error'
          client.emit 'ws:datagram', data
          return
        if data.header.type is 'JoinRoom'
          if data.body.room_id
            client.join data.body.room_id
            data.body.status = 'success'
            client.emit 'ws:datagram', data
          return
        if data.header.type is 'LeaveRoom'
          client.leave data.header.room_id
          data.body.status = 'success'
          client.emit 'ws:datagram', data
          return
        # console.log data
        (if typeof data.header.room_id is 'undefined' or data.header.room_id is null then io.sockets else io.in data.header.room_id).emit 'ws:datagram', data
      for listener of listeners
        client.removeListener listener, l if (l = client._events[listener])? and typeof l is 'function'
        client.on listener, listeners[listener]
      client