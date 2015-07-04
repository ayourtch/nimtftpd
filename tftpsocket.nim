import rawsockets as rs
import net
import os
import strutils
import streams
import tftp
import times


type UDPPacket = object
  data*: string
  address*: string
  port*: Port


type
  TFTPSocket* = ref TFTPSocketObj
  TFTPSocketObj = object of RootObj
    sock*: Socket
    create_hook*: proc(parent, child: TFTPSocket)
    destroy_hook*: proc(this: TFTPSocket)
    last_event_time: float
    timeout: float

type RRQSocket = ref object of TFTPSocket
  stream*: Stream
  seq*: uint16
  offset*: int
  seen_eof: bool
  address: string
  port: Port
  blocksize: int

type WRQSocket = ref object of TFTPSocket
  address: string
  port: Port

# implementations

# TFTP Socket

proc initTFTPSocket(tftp: TFTPSocket) =
  tftp.sock = newSocket(typ = SOCK_DGRAM, protocol = IPPROTO_UDP, buffered = false)

proc newTFTPSocket*(port: Port): TFTPSocket =
  new(result)
  initTFTPSocket(result)
  result.sock.bindAddr(port)

proc recvPacket*(s: TFTPSocket, length: int): UDPPacket =
  var sock = s.sock
  var data = repeatChar(length)
  var address: string
  var port: Port
  if sock.recvFrom(data, length, address, port) > 0:
    # echo(res, " ", length, " ", address, " ", port, " => ", data)
    result = UDPPacket(data: data, address: address, port: port)

method timerEvent(tftp: TFTPSocket) =
  discard

method checkTimer*(tftp: TFTPSocket, timenow: float) =
  if tftp.timeout > 0:
    if timenow - tftp.last_event_time >= tftp.timeout:
      tftp.timerEvent()
      tftp.last_event_time = timenow

proc newRRQSocket(parent: TFTPSocket, fname: string, address: string, port: Port, opts: TFTPOptions): RRQSocket
proc newWRQSocket(parent: TFTPSocket, fname: string, address: string, port: Port): WRQSocket

method handlePacket*(tftp: TFTPSocket, pkt: UDPPacket) =
  # echo("TFTP Idle socket")
  echo($(pkt.data.getPacketType), " ", pkt.data.getFileName, " ", pkt.data.getMode, " ", pkt.data.getOptions)
  case pkt.data.getPacketType
  of RRQ:
    var (fname, mode, opts) = pkt.data.getReqParams
    var rrq = newRRQSocket(tftp, fname, pkt.address, pkt.port, opts)
    if nil != rrq:
      if tftp.create_hook != nil:
        tftp.create_hook(tftp, rrq)
    else:
      var err = makeErr(1) & "Could not open file\0"
      discard tftp.sock.sendto(pkt.address, pkt.port, err)

  of WRQ:
    var wrq = newWRQSocket(tftp, pkt.data.getFileName, pkt.address, pkt.port)
    if tftp.create_hook != nil:
      tftp.create_hook(tftp, wrq)
  else:
    echo("Received ", pkt.data.getPacketType)

# RRQ Socket

proc rrqSendData(tftp: RRQSocket) =
  var data = repeatChar(tftp.blocksize)
  tftp.stream.setPosition(tftp.offset)
  data = tftp.stream.readStr(tftp.blocksize)
  var reply = makeData(tftp.seq, data)
  discard tftp.sock.sendTo(tftp.address, tftp.port, reply)
  tftp.seen_eof = data.len < tftp.blocksize
  if data.len == 0:
    echo("Zero data")

proc rrqEof(tftp: RRQSocket): bool =
  result = tftp.seen_eof # tftp.stream.atEnd

proc rrqAdvance(tftp: RRQSocket) =
  inc(tftp.seq)
  inc(tftp.offset, tftp.blocksize)

proc rrqSendOack(tftp: RRQSocket, opts: TFTPOptions) =
  var reply = makeOack(opts)
  discard tftp.sock.sendTo(tftp.address, tftp.port, reply)

method timerEvent(tftp: RRQSocket) =
  echo("RRQ timer")
  discard

proc newRRQSocket(parent: TFTPSocket, fname: string, address: string, port: Port, opts: TFTPOptions): RRQSocket =
  var stream = newFileStream(fname, fmRead)
  if nil != stream:
    var newOpts: TFTPOptions = @[]
    new(result)
    initTFTPSocket(result)
    result.blocksize = 512
    result.stream = stream
    result.seq = 1
    result.offset = 0
    result.address = address
    result.port = port
    result.timeout = 1
    for opt in opts:
      echo("OPT: ", opt.name, " = ", opt.value)
      if opt.name == "blksize":
        echo("Found blocksize: ", opt.value)
        result.blocksize = 1428
        newOpts.add(TFTPOption(name: "blksize", value: $(result.blocksize)))
    if newOpts.len > 0:
      result.rrqSendOack(newOpts)
    else:
      result.rrqSendData

method handlePacket(tftp: RRQSocket, pkt: UDPPacket) =
  # echo("RRQ socket")
  case pkt.data.getPacketType
  of ACK:
    if tftp.rrqEof:
      if tftp.destroy_hook != nil:
        tftp.destroy_hook(tftp)
    else:
      if pkt.data.getSeq.int32 > 0:
        tftp.rrqAdvance
      tftp.rrqSendData
  else:
    echo("Received ", pkt.data.getPacketType)


# WRQ Socket

proc wrqSendAck(tftp:WRQSocket, ackNum: uint16) =
  var ack = makeAck(ackNum)
  discard tftp.sock.sendto(tftp.address, tftp.port, ack)

proc newWRQSocket(parent: TFTPSocket, fname: string, address: string, port: Port): WRQSocket =
  new(result)
  initTFTPSocket(result)
  result.address = address
  result.port = port
  result.wrqSendAck(0)

method handlePacket(tftp: WRQSocket, pkt: UDPPacket) =
  # echo("WRQ socket")
  case pkt.data.getPacketType
  of DATA:
    var seq = pkt.data.getSeq
    var reply = makeAck(seq)
    let datalen = pkt.data.getData.len
    discard tftp.sock.sendTo(pkt.address, pkt.port, reply)
    if datalen == 512:
      echo("Getting more packets")
    else:
      echo("Last packet received, unregister socket");
  else:
    echo("Received ", pkt.data.getPacketType)


