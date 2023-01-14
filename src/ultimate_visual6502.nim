import motherboard
import std/monotimes
from times import inMilliseconds
from std/streams import newFileStream

var app_code = [
    0xA9, 0x50,         # lda #$FF
    0x8D, 0x00, 0x10,   # sta $1000
    0xCE, 0x00, 0x10,   # dec $1000
    0x4C, 0x05, 0xE0    # jmp $E002
]

when isMainModule:
  let transDefsFS = newFileStream("transdefs.txt", fmRead)
  let segDefsFS = newFileStream("segdefs.txt", fmRead)

  var m = Motherboard.init(transDefsFS, segDefsFS)

  # initialize the rom with our application
  for i, v in app_code:
    m.rom.memory[i] = cast[uint8](v)

  # set the 6502 reset vectors for the starting address of the app: $E000
  m.rom.memory[0x1FFC] = 0x00
  m.rom.memory[0x1FFD] = 0xE0

  # run the CPU for a short time
  let strt = getMonotime()
  for i in countup(1, 10000):
    m.clockTick()
  let elpsd = (getMonotime() - strt).inMilliseconds
  echo "elapsed time: ", elpsd
