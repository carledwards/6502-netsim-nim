import motherboard

when isMainModule:
  echo("Hello, World!")
  var m = new(Motherboard)


# import { CpuRunner } from "./cpu-runner";
# import { Motherboard } from '../motherboard';
# import { Ram } from "../components/ram";
# import { Rom } from "../components/rom";
# import { InterruptGenerator } from "../components/interrupt-generator";
# import { Via6522 } from "../components/via-6522";


# /**
#  * Helpers
#  */
# function toHexByte(val: number): string {
#     return val.toString(16).toUpperCase().padStart(2, '0')
# }
# function toHexWord(val: number): string {
#     return val.toString(16).toUpperCase().padStart(4, '0')
# }


# /**
#  * CPU glue setup
#  */
# let runner = new CpuRunner();

# let motherboard = new Motherboard(
#   runner,
#   1
# );

# // install 8k of RAM
# motherboard.getComponentManager().add(
#     0x0000, 
#     new Ram(0x2000));

# // install 8k of ROM
# let rom = new Rom(0x2000);
# motherboard.getComponentManager().add(
#     // install the ROM up high so we can have the RESET and IRQ vectors
#     0xE000, 
#     rom);

# // generate interrupts to blink LED-IRQ and LED-NMI
# motherboard.getComponentManager().add(0xA000, 
#     new InterruptGenerator());

# // VIA6522
# let via6522 = new Via6522();
# motherboard.getComponentManager().add(0xB000, via6522);

# // Reset Code
# let reset_code = [
#     0xA9, 0xFF,         // lda #$FF
#     0x8D, 0x02, 0xB0,   // sta $B002 - set all of PORTB to outputs
#     0x8D, 0x03, 0xB0,   // sta $B003 - set all of PORTA to outputs

#     0xA9, 0x64,         // lda #$64 
#     0x8D, 0x00, 0xA0,   // sta $A000 - set IRQ to every 10 seconds

#     0xA9, 0xFF,         // lda #$FF
#     0x8D, 0x01, 0xA0,   // sta $A001 - set NMI to every ~25 seconds

#     0x58,               // cli - allow interrupts

#     0xEA,               // nop
#     0x4C, 0x13, 0xE0    // jmp $E013 (back to the nop)
# ];

# // copy in the reset/startup code
# for (var i = 0x0000; i < reset_code.length; i++) {
#     rom.program[i] = reset_code[i];
# }
# // punch in the reset jump vectors
# rom.program[0x1FFC] = 0x00;
# rom.program[0x1FFD] = 0xE0;


# // IRQ Code
# let irq_code = [
#     0xEE, 0x01, 0xB0,   // inc $B001 - increment PORTA value
#     0x48,               // pha
#     0xA9, 0x00,         // lda #$00
#     0x8D, 0x02, 0xA0,   // sta $A002 - reset IRQ counter and remove it from the bus
#     0x68,               // pla
#     0x40                // rti
# ];

# // copy in the IRQ code
# for (var i = 0; i < irq_code.length; i++) {
#     rom.program[i + 0x1100] = irq_code[i];
# }
# // punch in the IRQ jump vectors
# rom.program[0x1FFE] = 0x00;
# rom.program[0x1FFF] = 0xF1;

# // NMI Code
# let nmi_code = [
#     0xEE, 0x00, 0xB0,   // inc $B000 - increment PORTB value
#     0x48,               // pha
#     0xA9, 0x00,         // lda #$00
#     0x8D, 0x03, 0xA0,   // sta $A003 - reset NMI counter
#     0x68,               // pla
#     0x40                // rti
# ];

# // copy in the NMI code
# for (var i = 0; i < nmi_code.length; i++) {
#     rom.program[i + 0x1200] = nmi_code[i];
# }
# // punch in the NMI jump vectors
# rom.program[0x1FFA] = 0x00;
# rom.program[0x1FFB] = 0xF2;

# via6522.on("PORTA", (prevValue:number, newValue:number) => {
#     console.log (`\n\nPORT-A LED: 0b${newValue.toString(2).padStart(8, '0')}\n\n`);
# });

# via6522.on("PORTB", (prevValue:number, newValue:number) => {
#     console.log (`\n\nPORT-B LED: 0b${newValue.toString(2).padStart(8, '0')}\n\n`);
# });

# function runTheClock() {
#     for(var i=0; i < 100; i++) {
#         motherboard.step();
#     }
#     setImmediate(runTheClock)
# }

# // reset the motherboard and start it up
# runner.onReset();
# motherboard.reset();
# runTheClock()
