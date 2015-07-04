discard """

TFTP: an implementation of TFTP packet parsing

Copyright (C) 2015 Andrew Yourtchenko. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

[ MIT license: http://www.opensource.org/licenses/mit-license.php ]
"""



import rawsockets as rs
import net
import os
import strutils
import selectors

type TFTPOperation* = enum
  RRQ = 1, WRQ, DATA, ACK, ERROR, OACK

type TFTPOption* = object
  name*: string
  value*: string

type TFTPOptions* = seq[TFTPOption]


proc getPacketType*(pkt: string): TFTPOperation =
  result = RRQ
  result.inc(pkt[1].ord + 256*pkt[0].ord - 1)

proc getString(pkt: string, start: int): tuple[str: string, fin: int] =
  var ret_str = ""
  var i = start
  while i < pkt.len and pkt[i].ord != 0:
    add(ret_str, pkt[i])
    inc(i)
  result = (str: ret_str, fin: i+1)

proc getOptionsSeq(pkt: string, i: int): TFTPOptions =
  var opts: TFTPOptions = @[]
  var i = i
  while i < pkt.len:
    var (name, i1) = getString(pkt, i)
    var (value, i2) = getString(pkt, i1)
    i = i2
    opts.add(TFTPOption(name: name, value: value))
  result = opts

proc getReqParams*(pkt: string): tuple[fname, mode: string, opts: TFTPOptions] =
  var (fname, i) = getString(pkt, 2)
  var (mode, j) = getString(pkt, i)
  var opts = getOptionsSeq(pkt, j)
  result = (fname: fname, mode: mode, opts: opts)

proc getFileName*(pkt: string): string =
  var (fname, fin) = getString(pkt, 2)
  result = fname

proc getOptions*(pkt: string): string =
  result = ""
  var i: int = 2
  while i < pkt.len and pkt[i].ord != 0:
    inc(i)
  while i < pkt.len:
    if char(0) == pkt[i]:
      add(result, ':')
    else:
      add(result, pkt[i])
    inc(i)


proc getMode*(pkt: string): string =
  result = ""
  var i: int = pkt.getFileName.len + 2 + 1
  while i < pkt.len and pkt[i].ord != 0:
    add(result, pkt[i])
    inc(i)

proc getSeq*(pkt: string): uint16 =
  result = pkt[3].ord + 256*pkt[2].ord


proc getData*(pkt: string): string =
  result = pkt[4..pkt.len]

proc seqToBytes*(seq: uint16): string =
  result = chr(seq.int32 shr 8) & chr (seq.int32 mod 256)

proc makeData*(seq: uint16, data: string): string =
  result = chr(0) & chr(ord(DATA)) & seqToBytes(seq) & data

proc makeAck*(seq: uint16): string =
  result = chr(0) & chr(ord(ACK)) & seqToBytes(seq)

proc makeErr*(seq: uint16): string =
  result = chr(0) & chr(ord(ERROR)) & seqToBytes(seq)

proc makeOack*(opts: TFTPOptions): string =
  var str = ""
  for opt in opts:
    add(str, opt.name)
    add(str, char(0))
    add(str, opt.value)
    add(str, char(0))
  result = chr(0) & chr(ord(OACK)) & str

