import constructor/constructor
import cpu/v6502
import components/memory

const
  RamSize = 8*1024 # 8k
  RomSize = 8*1024 # 8k
  RamBaseAddress = 0x0000
  RomBaseAddress = 0xE000

type
  Motherboard* = ref object
    name: string
    cpu: Cpu
    ram: Memory
    rom*: Memory
    onBusRead: ReadFromBusProc
    onBusWrite: WriteToBusProc

proc run*(t: Motherboard) =
  while true:
    t.cpu.halfStep()

proc clockTick*(t: Motherboard) =
  t.cpu.halfStep()

proc setupCpu(t: Motherboard) = 
  t.onBusRead = proc(busAddress: int): uint8 = 
    if busAddress < RamBaseAddress + RamSize:
      #echo "bus read ram ", busAddress
      result = t.ram.cpuRead(busAddress)
    elif busAddress >= RomBaseAddress:
      #echo "bus read rom ", busAddress
      result = t.rom.cpuRead(busAddress - RomBaseAddress)
    else:
      result = 0x00

  t.onBusWrite = proc(busAddress: int, value: uint8) = 
    if busAddress < RamBaseAddress + RamSize:
      #echo "bus write ram: ", busAddress, " ", value
      t.ram.cpuWrite(busAddress - RamBaseAddress, value)
    else:
      echo "bus write unknown: ", busAddress, " ", value

  t.cpu = Cpu.init(t.onBusRead, t.onBusWrite)
  t.cpu.reset()

proc init*(T: typedesc[Motherboard]): Motherboard {.constr.} =
  result.ram = Memory.init(RamSize, false)
  result.rom = Memory.init(RomSize, true)
  result.setupCpu()
