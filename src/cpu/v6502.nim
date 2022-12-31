import constructor/constructor
import std/tables
import chipdefs
import std/monotimes
from times import inMilliseconds

const NGND  = 558  # vss
const NPWR  = 657  # vcc
const NCLK0 = 1171 # clock 0
const NRDY  = 89   # ready
const NSO   = 1672 # stack overflow
const NNMI  = 1297 # non maskable interrupt
const NIRQ  = 103  # interrupt
const NRES  = 159  # reset
const NRW   = 1156 # read/write

const debug = false

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
# Globals
#
var gTransistorTable = newOrderedTable[int, Transistor]()
var gNodeDefs: array[1725, Node]
var gGndNode: Node
var gPwrNode: Node
var gRecalcNodeGroup = newSeq[Node]()


#
# Procedures
#
proc setupTransistors() =
  for item in transdefs:
    var c1 = item[2]
    var c2 = item[3]
    if c1 == NGND:
      c1 = c2
      c2 = NGND
    if c1 == NPWR:
      c1 = c2
      c2 = NPWR
    var trans = Transistor.init(item[0], item[1], c1, c2)
    gTransistorTable[trans.id] = trans

proc setupNodes() =
  for item in segdefs:
    if isNil(gNodeDefs[item[0]]):
      var node = Node.init(item[0], false, bool(item[1]))
      gNodeDefs[node.id] = node

proc connectTransistors() =
  for key, trans in gTransistorTable:
    gNodeDefs[trans.gateNodeId].gateTransistors.add(trans)
    gNodeDefs[trans.c1NodeId].c1c2Transistors.add(trans)
    gNodeDefs[trans.c2NodeId].c1c2Transistors.add(trans)

proc initChip() = 
  setupTransistors()
  setupNodes()
  connectTransistors()

proc getNodeValue(): bool =
  if gGndNode.inNodeGroup:
    result = false
  elif gPwrNode.inNodeGroup:
    result = true
  else:
    for node in gRecalcNodeGroup:
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

proc addSubNodesToGroup(node: Node) = 
  if node.inNodeGroup:
    return

  gRecalcNodeGroup.add(node)
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
    addSubNodesToGroup(gNodeDefs[targetCNodeId])

proc addRecalcNode(nodeId: int, recalcList: var OrderedTableRef[int, Node]) = 
  if nodeId == NGND or nodeId == NPWR:
    return
  let node = gNodeDefs[nodeId]
  recalcList[node.id] = node

proc turnTransistorOn(transistor: Transistor, recalcList: var OrderedTableRef[int, Node]) =
  when debug:
    echo "ton:  t" & $transistor.id & " : " & $transistor.on
  if transistor.on:
    return
  transistor.on = true
  addRecalcNode(transistor.c1NodeId, recalcList)

proc turnTransistorOff(transistor: Transistor, recalcList: var OrderedTableRef[int, Node]) =  
  when debug:
    echo "toff: t" & $transistor.id & " : " & $transistor.on
  if transistor.on == false:
    return
  transistor.on = false
  addRecalcNode(transistor.c1NodeId, recalcList)
  addRecalcNode(transistor.c2NodeId, recalcList)

proc recalcNode(node: Node, recalcList: var OrderedTableRef[int, Node]) =
  if node.id == NGND or node.id == NPWR:
    return

  when debug:
    var pulldownVal = "undefined"
    if node.pulldown == 0:
      pulldownVal = "false"
    elif node.pulldown == 1:
      pulldownVal = "true"
    echo "recalc node: " & $node.id & " " & $node.pullup & ", " & $pulldownVal & ", " & $node.state

  setLen(gRecalcNodeGroup, 0)
  addSubNodesToGroup(node)

  let newState = getNodeValue()
  when debug:
    echo "getNodeValue returned: " & $newState
  for nodeVal in gRecalcNodeGroup:
    nodeVal.inNodeGroup = false
    when debug:
      echo "group id: " & $nodeVal.id & ": " & $nodeVal.state & ": " & $newState
    if nodeVal.state == newState:
      continue
    nodeVal.state = newState
    for tran in nodeVal.gateTransistors:
      if newState:
        turnTransistorOn(tran, recalcList)
      else:
        turnTransistorOff(tran, recalcList)

proc recalcNodeList(recalcList: OrderedTableRef[int, Node]) =
  var currentRecalcList = recalcList
  var nextRecalcList = newOrderedTable[int, Node]()
  while currentRecalcList.len > 0:
    for key, val in currentRecalcList:
      recalcNode(val, nextRecalcList)
    currentRecalcList = nextRecalcList
    nextRecalcList = newOrderedTable[int, Node]()

proc setLow(node: var Node) =
  node.pullup = false
  node.pulldown = 1
  var list = newOrderedTable[int, Node]()
  list[node.id] = node
  recalcNodeList(list)

proc setHigh(node: var Node) =
  node.pullup = true
  node.pulldown = 0
  var list = newOrderedTable[int, Node]()
  list[node.id] = node
  recalcNodeList(list)

proc reset() =
  for i in 0..1724:
    if not isNil(gNodeDefs[i]):
      gNodeDefs[i].state = false
      gNodeDefs[i].inNodeGroup = false

  gGndNode = gNodeDefs[NGND]
  gGndNode.state = false

  gPwrNode = gNodeDefs[NPWR]
  gPwrNode.state = true

  for key, val in gTransistorTable:
    val.on = false

  var clk0 = gNodeDefs[NCLK0]
  setLow(gNodeDefs[NRES])
  when debug:
    echo "clk0 start 0 " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
  setLow(clk0)
  when debug:
    echo "clk0 start 1 " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
  setHigh(gNodeDefs[NRDY])
  setLow(gNodeDefs[NSO])
  setHigh(gNodeDefs[NIRQ])
  setHigh(gNodeDefs[NNMI])
  when debug:
    echo "clk0 start 2 " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state

  var allNodes = newOrderedTable[int, Node]()
  for i in 0..1724:
    if not isNil(gNodeDefs[i]):
      allNodes[gNodeDefs[i].id] = gNodeDefs[i]
  recalcNodeList(allNodes)
  when debug:
    echo "clk0 start 3 " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
  for i in 0..7:
    setHigh(clk0)
    when debug:
      echo "clk0 high: " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
    setLow(clk0)
    when debug:
      echo "clk0 low:  " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
  
  setHigh(gNodeDefs[NRES])
  
  for i in 0..5:
    setHigh(clk0)
    when debug:
      echo "clk0 high: " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state
    setLow(clk0)
    when debug:
      echo "clk0 low:  " & $gNodeDefs[1155].state & ", " & $gNodeDefs[558].state & ", " & $gNodeDefs[252].state

proc halfStep() = 
  var clk0 = gNodeDefs[NCLK0]
  if clk0.state:
    setLow(clk0)
  else:
    setHigh(clk0)

when isMainModule:
  initChip()
  reset()

  when not debug:
    let strt = getMonotime()
    for i in (0 .. 10000):
      halfStep()
    let elpsd = (getMonotime() - strt).inMilliseconds
    echo "elapsed time: ", elpsd