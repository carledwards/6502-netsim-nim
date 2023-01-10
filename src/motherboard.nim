import constructor/constructor
import cpu/v6502
import components/memory

const RamSize = 8*1024 # 8k
const RomSize = 8*1024 # 8k
const RamBaseAddress = 0x0000
const RomBaseAddress = 0xE000

type
  Motherboard* = ref object
    name: string
    cpu: Cpu
    ram: Memory
    rom: Memory
    onBusRead: ReadFromBusProc
    onBusWrite: WriteToBusProc

proc run*(t: Motherboard) =
  while true:
    t.cpu.halfStep()


proc step*(t: Motherboard) =
  t.cpu.halfStep()


proc setupCallbacks(t: Motherboard) = 
  t.onBusRead = proc(busAddress: int): uint8 = 
    echo "bus read", busAddress, $t.name
    result = 0xEA

  t.onBusWrite = proc(busAddress: int, value: uint8) = 
    echo "bus write", busAddress, $t.name

  t.cpu = Cpu.init(t.onBusRead, t.onBusWrite)
  # t.cpu = Cpu.init(proc(busAddress: int): int8 = echo $t.step(); 1, proc(busAddress: int, data: int8) = echo $t)

proc init*(T: typedesc[Motherboard]): Motherboard {.constr.} =
  result.ram = Memory.init(8*1024, false)
  result.rom = Memory.init(8*1024, true)
  result.setupCallbacks
  result.cpu.reset

when isMainModule:
  var motherboard = Motherboard.init()
  for i in countup(1, 30):
    motherboard.step
