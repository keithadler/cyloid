# Cyloid

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A tank shooter for the Atari 2600, written in 6502 assembly by **Keith Adler**. Open source under the MIT license.

## 🎮 Play in Browser

[**Play Cyloid Now**](https://javatari.org?ROM=https://raw.githubusercontent.com/keithadler/cyloid/refs/heads/main/cyloid.rom)

Arrow keys to move, Space to fire.

## Build

```bash
brew install dasm        # macOS (or download from https://github.com/dasm-assembler/dasm)
make
```

Produces `game.bin` and `cyloid.rom` — a 4KB NTSC Atari 2600 ROM.

## Play Locally

```bash
brew install --cask stella
open -a Stella cyloid.rom
```

### Controls (Stella)

| Key | Action |
|-----|--------|
| Arrow keys | Move tank |
| Space | Fire missile |
| F1 | Select |
| F2 | Reset |

---

## Game Overview

Navigate your tank through obstacle-filled arenas, destroy all targets to advance, and survive the homing boss attacks.

### Objective

- Destroy all targets on each level to advance
- Survive 8 levels with increasing difficulty
- Score 99 points to win
- Targets = 1-5 points (streak bonus), Boss = 0 points (obstacle only)

### Lives

- 3 lives per game
- Remaining lives shown as cyan pips in the top border
- Death triggers a 45-frame explosion animation at the death location
- Tank respawns at center-bottom after explosion
- 45 frames of invincibility after respawn

### Enemies

- **Targets** (colored diamonds): 2-5 per level, bounce off walls
  - Speed increases with level
  - Last 1-2 targets move at double speed
- **Boss** (bright yellow): homing kamikaze attacker
  - Appears every ~4 seconds from a random edge
  - Homes directly toward player position
  - Speed scales with level (2px/update → 4px/update)
  - Resets when it kills the player
  - Shooting it triggers an explosion but awards no points

### Scoring

- Each target hit scores 1 + streak bonus (consecutive hits without missing)
- Streak: 1st hit = 1pt, 2nd = 2pt, 3rd = 3pt, 4th = 4pt, 5th+ = 5pt
- Streak resets when missile hits a wall or goes off-screen
- Screen flashes white when a level is completed

### Obstacles

- Playfield walls appear in horizontal bands across the field
- Density increases with level (sparse on level 0, dense by level 5+)
- Touching walls kills the player
- Missiles stop when hitting walls (with a sound effect)
- Pattern randomized each level using LFSR

### Levels

8 levels (0-7) that cycle, each with unique:
- Field/wall/target color palette
- Obstacle density (controlled by per-level bitmask)
- Target movement directions and speed
- Boss homing speed

### Title Sequence

| Screen | Technique | Duration |
|--------|-----------|----------|
| KEITH | Reflected PF text | 3 sec |
| ADLER | Reflected PF text | 2.5 sec |
| PRESENTS | Asymmetric PF (no mirror) | 2.5 sec |
| CYLOID | Asymmetric PF + P0 tank flyby | 3 sec |
| Black | Blank | 1.5 sec |

### Game Flow

```
Title Sequence → Gameplay (wait for first move)
  ↓ (all targets destroyed)
Level Score Screen (victory jingle) → Next Level
  ↓ (last life lost)
Final Score Screen (sad melody) → GAME OVER (somber melody) → Title
  ↓ (score reaches 99)
Final Score Screen → GAME OVER → Title
```

---

## Technical Architecture

This section is a reference for anyone learning Atari 2600 programming. The 2600 has no frame buffer — the CPU must feed graphics data to the TIA chip in real-time as the electron beam scans each line ("racing the beam").

### The Hardware

| Component | Details |
|-----------|---------|
| CPU | 6507 (6502 variant), 1.19 MHz |
| Graphics | TIA (Television Interface Adapter) |
| RAM | 128 bytes ($80-$FF), shared with stack |
| ROM | 4KB at $F000-$FFFF (bankswitching for larger) |
| Input | 2 joystick ports, console switches |
| Audio | 2 channels, 32 frequencies, 16 waveforms |

### TIA Objects

The TIA provides 5 movable objects. That's ALL you get — no tiles, no sprites, no layers:

| Object | Width | Cyloid Usage |
|--------|-------|-------------|
| Player 0 (P0) | 8 pixels | Tank sprite (4 directional graphics) |
| Player 1 (P1) | 8 pixels | Targets (flickered) + Boss (yellow) |
| Missile 0 (M0) | 1-8 clocks | Player bullet |
| Missile 1 (M1) | 1-8 clocks | Unused |
| Ball (BL) | 1-8 clocks | Unused |
| Playfield (PF) | 40 pixels | Obstacles, walls, title text, lives |

### Playfield Registers

The playfield is 40 pixels wide, defined by 3 registers (20 pixels, mirrored or repeated):

```
PF0: 4 pixels  (bits 4,5,6,7 → pixels 0-3)
PF1: 8 pixels  (bits 7,6,5,4,3,2,1,0 → pixels 4-11)  ← reversed!
PF2: 8 pixels  (bits 0,1,2,3,4,5,6,7 → pixels 12-19)
```

In reflect mode (CTRLPF bit 0 = 1), the right half mirrors the left. In repeat mode, it duplicates.

### Frame Timing

NTSC requires exactly 262 scanlines per frame at 60 Hz:

```
VSYNC:     3 lines  — Tell TV to start new frame
VBLANK:   37 lines  — CPU processing time (game logic runs here)
Visible:  192 lines  — The picture (kernel runs here)
Overscan:  30 lines  — More CPU time (cleanup)
Total:    262 lines
```

Each scanline = 76 CPU cycles. The kernel must complete ALL graphics updates within 76 cycles per line or the display glitches.

### VBLANK Timer

Instead of counting scanlines manually during VBLANK, use the RIOT timer:

```asm
lda #43         ; 43 × 64 = 2752 cycles ≈ 37 scanlines
sta TIM64T      ; Start timer
; ... do game logic ...
lda INTIM       ; Check timer
bne .-2         ; Wait until expired
sta WSYNC       ; Sync to scanline boundary
```

### Kernel Design

Cyloid uses a **2-line kernel** — each iteration draws 2 scanlines:

```
Line 1: Obstacle PF check + Tank sprite (P0)     — max 72 cycles
Line 2: Target sprite (P1) + Missile (M0)         — max 58 cycles
```

The obstacle check uses a bitmask trick:
```asm
txa             ; current scanline
and #$1F        ; modulo 32
cmp #$18        ; >= 24?
bcc .noObstacle ; if not, skip
; Show obstacle band...
```

This creates 8-scanline obstacle bands every 32 lines with zero per-line data lookups.

### Horizontal Positioning

The 2600 has no X-position registers. To position an object horizontally, you use the "divide by 15" trick:

```asm
lda ObjectX     ; desired X position (0-159)
sec
sta WSYNC       ; wait for start of line
.loop:
sbc #15         ; subtract 15 (one TIA "section")
bcs .loop       ; keep going until negative
eor #7          ; convert remainder to fine motion
asl
asl
asl
asl
sta HMxx        ; set fine motion (-8 to +7 pixels)
sta RESxx       ; set coarse position (where the loop ended)
sta WSYNC
sta HMOVE       ; apply fine motion
```

### Asymmetric Playfield

For non-mirrored text (PRESENTS, CYLOID, GAME OVER), Cyloid updates PF registers mid-scanline:

```
Cycle  0-21: Write left-half PF0, PF1, PF2
Cycle 21-41: NOP sled (10 NOPs = 20 cycles)
Cycle 41-62: Write right-half PF2, PF1, PF0 (reflect mode reversal)
```

In reflect mode, the right half draws PF2 first (cycle ~44), then PF1 (~52), then PF0 (~60). By updating registers between the left and right draw windows, each half shows different data.

### Flicker Multiplexing

With only 2 player sprites, Cyloid shows up to 5 targets + 1 boss by cycling which one P1 draws each frame:

```
Frame 1: P1 = Target 0
Frame 2: P1 = Boss
Frame 3: P1 = Target 1
Frame 4: P1 = Boss
Frame 5: P1 = Target 2
...
```

At 60fps, each object appears at 12-30fps — visible flicker but playable. This is the same technique used by Space Invaders on the 2600.

### Collision Detection

The TIA provides hardware collision registers — latches that set when objects overlap on screen:

| Register | Bits | Cyloid Usage |
|----------|------|-------------|
| CXP0FB | bit 7: P0-PF | Tank vs walls (death) |
| CXPPMM | bit 7: P0-P1 | Tank vs target/boss (death) |
| CXM0FB | bit 7: M0-PF | Missile vs walls (stop bullet) |
| CXCLR | write-any | Clear all collision latches |

Missile vs target uses **software collision** (distance check) because the missile and targets are on different frames due to the frame-split architecture.

### Frame-Split Architecture

Game logic is too heavy for one VBLANK period. Cyloid splits work across two frames:

```
EVEN frames: Missile movement, hit detection (2 targets + boss)
ODD frames:  Wall collision, death timers, target movement, flicker, boss AI, player collision
EVERY frame: Joystick, fire button, flash/respawn, tank graphics, sound
```

This halves the worst-case VBLANK time from ~1800 cycles to ~900 cycles.

### Sound

The TIA has 2 audio channels, each with:
- `AUDCx` — waveform (0-15): pure tone, noise, buzz, etc.
- `AUDFx` — frequency divider (0-31): lower = higher pitch
- `AUDVx` — volume (0-15)

**Critical**: TIA registers are write-only. You cannot read back `AUDV0` to decay the volume — you must track it in RAM (`SndVol` variable).

### LFSR Random Number Generator

```asm
Random:
    lda RandSeed
    lsr             ; shift right, bit 0 → carry
    bcc .noTap
    eor #$B4        ; XOR with tap polynomial
.noTap:
    sta RandSeed    ; store new seed
    rts             ; random value in A
```

Produces 255 unique values before repeating. Seed must be non-zero.

### Memory Map

```
$0000-$002C  TIA registers (write)
$0030-$003D  TIA registers (read — collision, input)
$0080-$00FF  RAM (128 bytes)
  $80-$D8    Game variables (~88 bytes)
  $D9-$FF    Stack (~39 bytes, grows down from $FF)
$0280-$0297  RIOT registers (timer, I/O)
$F000-$FFF9  ROM (4086 bytes of code + data)
$FFFA-$FFFF  Vectors (NMI, RESET, IRQ — 6 bytes)
```

---

## Repository

| File | Description |
|------|-------------|
| `game.asm` | Main game source (~2000 lines, heavily commented) |
| `cyloid.rom` | Pre-built ROM (4KB, playable in any 2600 emulator) |
| `vcs.h` | TIA/RIOT register definitions (standard include) |
| `macro.h` | Standard macros: CLEAN_START, VERTICAL_SYNC, SLEEP |
| `Makefile` | Build automation (`make` to build, `make clean` to reset) |
| `CHANGELOG.md` | Complete version history (v0.1 through v1.0) |
| `LICENSE` | MIT License |

## Contributing

Contributions welcome! Fork the repo, make changes, and submit a pull request. The game is written in 6502 assembly for the [DASM assembler](https://github.com/dasm-assembler/dasm).

## Resources for Learning 2600 Programming

- [2600 Programming For Newbies](https://forums.atariage.com/topic/27221-session-9-6502-and-dasm-assembling-the-basics/) — AtariAge tutorial series
- [Stella Programmer's Guide](https://alienbill.com/2600/101/docs/stella.html) — TIA register reference
- [6502 Instruction Set](https://www.masswerk.at/6502/6502_instruction_set.html) — complete opcode reference
- [Atari 2600 Programming](https://8bitworkshop.com/v3.11.0/?platform=vcs) — 8bitworkshop online IDE

## Acknowledgments

- Created by **Keith Adler**
- [Javatari.js](https://javatari.org) by Paulo Augusto Peccin — browser-based Atari 2600 emulator that makes it possible to play Cyloid online
- [Stella](https://stella-emu.github.io) — the reference Atari 2600 emulator used during development
- [DASM](https://github.com/dasm-assembler/dasm) — the macro assembler for 6502
- The Atari 2600 homebrew community at [AtariAge](https://atariage.com) for decades of knowledge sharing

## License

This project is open source under the [MIT License](LICENSE).
