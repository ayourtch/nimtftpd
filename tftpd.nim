import rawsockets as rs
import net
import os
import strutils
import selectors
import streams
import tftp
import tftpsocket
import times


proc registerIn*(tftp: TFTPSocket, sel: Selector) =
  sel.register(tftp.sock.getFd, {EvRead}, tftp)


# Main

var selector = newSelector()
var allsockets: seq[TFTPSocket] = @[]


var data = newTFTPSocket(Port(12345))
var data2 = newTFTPSocket(Port(12346))

data.registerIn(selector)
data2.registerIn(selector)

proc child_destroy_hook(tftp: TFTPSocket) =
  selector.unregister(tftp.sock.getFd)
  for i in 0..allsockets.high:
    if allsockets[i] == tftp:
      allsockets.del(i)
      break

data.create_hook = proc(parent, child: TFTPSocket) =
  child.registerIn(selector)
  child.destroy_hook = child_destroy_hook
  allsockets.add(child)
  discard

while true:
  let ready = selector.select(100)
  if ready.len > 0:
    for i in 0..ready.len-1:
      if card(ready[i].events) > 0:
        var tftp = TFTPSocket(ready[i].key.data)
        var pkt = tftp.recvPacket(1000)
        tftp.handlePacket(pkt)
  var timenow = epochTime()
  for tftp in allsockets:
    tftp.checkTimer(timenow)


