var fs = require('fs');
var staticPath = require('serve-static');
var express = require('express');
var http = require('http');
var app = express(), 
host = process.env.HOST || '0.0.0.0',
port = process.env.PORT || 3000,
server = require('http').createServer(app),
websock = require('../dist/backbone-sock-client');
websock.init( io = require('socket.io').listen( server ) );

server.listen(port);

app.use( staticPath('dist') );

 
app.get("/", function(req, res) {
	res.sendFile(__dirname+'/index.html');
});

 
server.listen(port, host, function() {
	return console.log("\u001b[32mService available at: \u001b[36mhttp://" + host + ":" + port + "\u001b[0m");
});
 