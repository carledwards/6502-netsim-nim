import constructor/constructor

type
  Memory* = ref object
    size: int
    isReadOnly: bool
    memory: seq[int8]

proc init*(T: typedesc[Memory], size: int, isReadOnly: bool): Memory {.constr.} =
  result.size = size
  result.isReadOnly = isReadOnly
  result.memory = newSeq[int8](size)

proc cpuWrite*(t: Memory, address: int, data: int8) = 
  if not t.isReadOnly:
    t.memory[address] = data

proc cpuRead*(t: Memory, address: int): int8 = 
  result = t.memory[address]

proc reset*(t: Memory) =
  if not t.isReadOnly:
    for i in t.memory:
      t.memory[i] = 0