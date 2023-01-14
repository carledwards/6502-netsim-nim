import constructor/constructor
import std/tables
import std/math
import std/streams
import std/parsecsv
import strutils

const
  NGND  = 558  # vss
  NPWR  = 657  # vcc
  NCLK0 = 1171 # clock 0
  NRDY  = 89   # ready
  NSO   = 1672 # stack overflow
  NNMI  = 1297 # non maskable interrupt
  NIRQ  = 103  # interrupt
  NRES  = 159  # reset
  NRW   = 1156 # read/write

  NODE_DEF_COUNT = 1725
  debug = false

#
# Transistor definition
#
type
  Transistor = ref object
    id: int
    gateNodeId: int
    c1NodeId: int
    c2NodeId: int
    on: bool

proc init(T: typedesc[Transistor], id: int, gateNodeId: int, c1NodeId: int, c2NodeId: int): Transistor {.constr.} =
  result.on = false

proc `$`(o: Transistor): string =
  return "id: " & $o.id & ", gateNodeId: " & $o.gateNodeId & ", c1NodeId: " & $o.c1NodeId & ", c2NodeId: " & $o.c2NodeId & ", on: " & $o.on 

#
# Node definition
#
type
  Node* = ref object
    id*: int
    state*: bool
    pullup*: bool
    pulldown*: int
    gateTransistors*: seq[Transistor]
    c1c2Transistors*: seq[Transistor]
    inNodeGroup*: bool

proc init(T: typedesc[Node], id: int, state: bool, pullup: bool): Node {.constr.} =
  result.gateTransistors = newSeq[Transistor](0)
  result.c1c2Transistors = newSeq[Transistor](0)
  result.pulldown = -1
  result.inNodeGroup = false

proc `$`(o: Node): string =
  return "id: " & $o.id & ", state: " & $o.state & "pullup: " & $o.pullup & ", pulldown: " & $o.pulldown & ", gates: " & $o.gateTransistors & ", c1c2s: " & $o.c1c2Transistors 

#
# CPU
#
type
  ReadFromBusProc* = proc (busAddress: int): uint8 {.closure.}
  WriteToBusProc* = proc (busAddress: int, data: uint8) {.closure.}

  DataLine* {.size: sizeof(cint).} = enum
    D0
    D1
    D2
    D3
    D4
    D5
    D6
    D7
  DataLines = set[DataLine]

  AddressLine* {.size: sizeof(cint).} = enum
    A0
    A1
    A2
    A3
    A4
    A5
    A6
    A7
    A8
    A9
    A10
    A11
    A12
    A13
    A14
    A15
  AddressLines = set[AddressLine]

  Cpu* = ref object
    transistorTable: OrderedTable[int, Transistor]
    nodeDefs: array[NODE_DEF_COUNT, Node]
    gndNode: Node
    pwrNode: Node
    recalcNodeGroup: seq[Node]
    readFromBusProc*: ReadFromBusProc
    writeToBusProc*: WriteToBusProc
    addressLines: AddressLines
    dataLines: DataLines

const dataLineVals = [
  D0: 1005,
  D1: 82,
  D2: 945,
  D3: 650,
  D4: 1393,
  D5: 175,
  D6: 1591,
  D7: 1349
]

const addressLineVals = [
  A0  : 268,
  A1  : 451,
  A2  : 1340,
  A3  : 211,
  A4  : 435,
  A5  : 736,
  A6  : 887,
  A7  : 1493,
  A8  : 230,
  A9  : 148,
  A10 : 1443,
  A11 : 399,
  A12 : 1237,
  A13 : 349,
  A14 : 672,
  A15 : 195
]

template withDefinition(name: string, definitionFS: FileStream, columns: int, body: untyped) =
  var x : CsvParser
  open(x, definitionFS, name)
  type
    rowArray = array[0..(columns-1), int]
  var row {.inject.}: rowArray
  while readRow(x):
    if len(x.row) < columns:
      continue
    if x.row[0].startsWith("#"):
      continue
    for i, v in row:
      row[i] = parseInt(strip(x.row[i]))
    body
  close(x)

#
# Procedures
#
proc setupTransistors(t: var Cpu, definitionFS: FileStream) =
  withDefinition("transdefs", definitionFS, 4):
    var c1 = row[2]
    var c2 = row[3]
    if c1 == NGND:
      c1 = c2
      c2 = NGND
    if c1 == NPWR:
      c1 = c2
      c2 = NPWR
    var trans = Transistor.init(row[0], row[1], c1, c2)
    t.transistorTable[trans.id] = trans

proc setupNodes(t: var Cpu, definitionFS: FileStream) =
  withDefinition("segdefs", definitionFS, 2):
    if isNil(t.nodeDefs[row[0]]):
      var node = Node.init(row[0], false, bool(row[1]))
      t.nodeDefs[node.id] = node

proc connectTransistors(t: var Cpu) =
  for key, trans in t.transistorTable:
    t.nodeDefs[trans.gateNodeId].gateTransistors.add(trans)
    t.nodeDefs[trans.c1NodeId].c1c2Transistors.add(trans)
    t.nodeDefs[trans.c2NodeId].c1c2Transistors.add(trans)

proc init*(T: typedesc[Cpu], readFromBusProc: ReadFromBusProc, writeToBusProc: WriteToBusProc, transDefsFS: FileStream, segDefsFS: FileStream): Cpu {.constr.} =
  result.transistorTable = OrderedTable[int, Transistor]()
  result.recalcNodeGroup = newSeq[Node]()
  result.setupTransistors(transDefsFS)
  result.setupNodes(segDefsFS)
  result.connectTransistors()
  result.readFromBusProc = readFromBusProc
  result.writeToBusProc = writeToBusProc

proc getNodeValue(t: var Cpu): bool =
  if t.gndNode.inNodeGroup:
    result = false
  elif t.pwrNode.inNodeGroup:
    result = true
  else:
    for node in t.recalcNodeGroup:
      when debug:
        var pulldownVal = "undefined"
        if node.pulldown == 0:
          pulldownVal = "false"
        elif node.pulldown == 1:
          pulldownVal = "true"
        echo "getNodeValue: " & $node.id & " " & $node.pullup & ", " & $pulldownVal & ", " & $node.state

      # Order of these checks are significant.
      if node.pullup:
        result = true
        break
      elif node.pulldown == 1:
        result = false
        break
      elif node.state:
        result = true
        break

proc addSubNodesToGroup(t: var Cpu, node: Node) = 
  if node.inNodeGroup:
    return

  t.recalcNodeGroup.add(node)
  node.inNodeGroup = true
  when debug:
    echo "add node: " & $node.id
  if node.id == NGND or node.id == NPWR:
    return
  for transistor in node.c1c2Transistors:
    when debug:
      echo "trans: t" & $transistor.id & ": " & $transistor.on
    if transistor.on == false:
      continue
    let targetCNodeId = (if transistor.c1NodeId == node.id: transistor.c2NodeId else: transistor.c1NodeId)
    t.addSubNodesToGroup(t.nodeDefs[targetCNodeId])

proc addRecalcNode(t: var Cpu, nodeId: int, recalcList: var OrderedTableRef[int, Node]) = 
  if nodeId == NGND or nodeId == NPWR:
    return
  let node = t.nodeDefs[nodeId]
  recalcList[node.id] = node

proc turnTransistorOn(t: var Cpu, transistor: Transistor, recalcList: var OrderedTableRef[int, Node]) =
  when debug:
    echo "ton:  t" & $transistor.id & " : " & $transistor.on
  if transistor.on:
    return
  transistor.on = true
  t.addRecalcNode(transistor.c1NodeId, recalcList)

proc turnTransistorOff(t: var Cpu, transistor: Transistor, recalcList: var OrderedTableRef[int, Node]) =  
  when debug:
    echo "toff: t" & $transistor.id & " : " & $transistor.on
  if transistor.on == false:
    return
  transistor.on = false
  t.addRecalcNode(transistor.c1NodeId, recalcList)
  t.addRecalcNode(transistor.c2NodeId, recalcList)

proc recalcNode(t: var Cpu, node: Node, recalcList: var OrderedTableRef[int, Node]) =
  if node.id == NGND or node.id == NPWR:
    return

  when debug:
    var pulldownVal = "undefined"
    if node.pulldown == 0:
      pulldownVal = "false"
    elif node.pulldown == 1:
      pulldownVal = "true"
    echo "recalc node: " & $node.id & " " & $node.pullup & ", " & $pulldownVal & ", " & $node.state

  setLen(t.recalcNodeGroup, 0)
  t.addSubNodesToGroup(node)

  let newState = t.getNodeValue()
  when debug:
    echo "getNodeValue returned: " & $newState
  for nodeVal in t.recalcNodeGroup:
    nodeVal.inNodeGroup = false
    when debug:
      echo "group id: " & $nodeVal.id & ": " & $nodeVal.state & ": " & $newState
    if nodeVal.state == newState:
      continue
    nodeVal.state = newState
    for tran in nodeVal.gateTransistors:
      if newState:
        t.turnTransistorOn(tran, recalcList)
      else:
        t.turnTransistorOff(tran, recalcList)

proc recalcNodeList(t: var Cpu, recalcList: OrderedTableRef[int, Node]) =
  var currentRecalcList = recalcList
  var nextRecalcList = newOrderedTable[int, Node]()
  while currentRecalcList.len > 0:
    for key, val in currentRecalcList:
      t.recalcNode(val, nextRecalcList)
    currentRecalcList = nextRecalcList
    nextRecalcList = newOrderedTable[int, Node]()

proc setLow(t: var Cpu, node: var Node) =
  node.pullup = false
  node.pulldown = 1
  var list = newOrderedTable[int, Node]()
  list[node.id] = node
  t.recalcNodeList(list)

proc setHigh(t: var Cpu, node: var Node) =
  node.pullup = true
  node.pulldown = 0
  var list = newOrderedTable[int, Node]()
  list[node.id] = node
  t.recalcNodeList(list)

proc reset*(t: var Cpu) =
  for i in 0..<NODE_DEF_COUNT:
    if not isNil(t.nodeDefs[i]):
      t.nodeDefs[i].state = false
      t.nodeDefs[i].inNodeGroup = false

  t.gndNode = t.nodeDefs[NGND]
  t.gndNode.state = false

  t.pwrNode = t.nodeDefs[NPWR]
  t.pwrNode.state = true

  for key, val in t.transistorTable:
    val.on = false

  var clk0 = t.nodeDefs[NCLK0]
  t.setLow(t.nodeDefs[NRES])
  when debug:
    echo "clk0 start 0 " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
  t.setLow(clk0)
  when debug:
    echo "clk0 start 1 " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
  t.setHigh(t.nodeDefs[NRDY])
  t.setLow(t.nodeDefs[NSO])
  t.setHigh(t.nodeDefs[NIRQ])
  t.setHigh(t.nodeDefs[NNMI])
  when debug:
    echo "clk0 start 2 " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state

  var allNodes = newOrderedTable[int, Node]()
  for i in 0..<NODE_DEF_COUNT:
    if not isNil(t.nodeDefs[i]):
      allNodes[t.nodeDefs[i].id] = t.nodeDefs[i]
  t.recalcNodeList(allNodes)
  when debug:
    echo "clk0 start 3 " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
  for i in 0..7:
    t.setHigh(clk0)
    when debug:
      echo "clk0 high: " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
    t.setLow(clk0)
    when debug:
      echo "clk0 low:  " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
  
  t.setHigh(t.nodeDefs[NRES])
  
  for i in 0..5:
    t.setHigh(clk0)
    when debug:
      echo "clk0 high: " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state
    t.setLow(clk0)
    when debug:
      echo "clk0 low:  " & $t.nodeDefs[1155].state & ", " & $t.nodeDefs[558].state & ", " & $t.nodeDefs[252].state

proc cpuRegReadAddressBusFromPads(t: var Cpu): int =
  for addressLine, nodeIndex in addressLineVals.pairs:
    if t.nodeDefs[nodeIndex].state:
      t.addressLines.incl(addressLine) 
    else: 
      t.addressLines.excl(addressLine)
  result = cast[int](t.addressLines)

proc cpuRegReadDataBusFromPads(t: var Cpu): int =
  for dataLine, nodeIndex in dataLineVals.pairs:
    if t.nodeDefs[nodeIndex].state: t.dataLines.incl(dataLine) else: t.dataLines.excl(dataLine)
  result = cast[int](t.dataLines)

proc handleBusRead(t: var Cpu) =
    if t.nodeDefs[NRW].state:
      let address = t.cpuRegReadAddressBusFromPads()
      let data = t.readFromBusProc(address)
      t.dataLines = cast[DataLines](data)

      # update each of the nodes with the data read from the bus
      var list = newOrderedTable[int, Node]()
      for dataLine, nodeIndex in dataLineVals.pairs:
        var node = t.nodeDefs[nodeIndex]
        list[node.id] = node
        if (2 ^ dataLine.ord and cast[int](data)) > 0:
          node.pulldown = 0
          node.pullup = true
        else:
          node.pulldown = 1
          node.pullup = false
      t.recalcNodeList(list)

proc handleBusWrite(t: var Cpu) =
  if not t.nodeDefs[NRW].state:
    let address = t.cpuRegReadAddressBusFromPads()
    let data = cast[uint8](t.cpuRegReadDataBusFromPads())
    t.writeToBusProc(address, data)

proc halfStep*(t: var Cpu) = 
  var clk0 = t.nodeDefs[NCLK0]
  if clk0.state:
    t.setLow(clk0)
    t.handleBusRead()
  else:
    t.setHigh(clk0)
    t.handleBusWrite()
