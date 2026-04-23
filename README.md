# Cyloid

A tank shooter for the Atari 2600, written in 6502 assembly.

## Build

```bash
brew install dasm        # macOS
make
```

Produces `game.bin` — a 4KB NTSC Atari 2600 ROM.

## Play

```bash
brew install --cask stella
open -a Stella game.bin
```

### Controls (Stella)

| Key | Action |
|-----|--------|
| Arrow keys | Move tank |
| Space | Fire missile |

## Game Overview

Navigate your tank through obstacle-filled arenas, destroy all targets to advance, and survive the homing boss attacks.

### Objective

- Destroy all targets on each level to advance
- Survive 8 levels with increasing difficulty
- Score 40 points to win
- Each target = 1 point, boss = 5 points

### Lives

- 3 lives per game
- Remaining lives shown as cyan pips in the top border
- Death triggers a 45-frame explosion animation at the death location
- Tank respawns at center-bottom (78, 170) after explosion

### Enemies

- **Targets** (green diamonds): 2-5 per level, bounce off walls
- **Boss** (bright yellow): homing kamikaze attacker, appears every ~4 seconds
  - Homes toward player position
  - Speed increases with level (2px → 3px → 4px per update)
  - Spawns from random edge (left or right)
  - Resets when it kills the player
  - Worth 5 points when shot

### Obstacles

- Playfield walls appear in horizontal bands across the field
- Density increases with level (sparse on level 0, dense by level 5+)
- Touching walls kills the player
- Missiles stop when hitting walls (with a sound effect)
- Pattern randomized each level

### Levels

8 levels (0-7) that cycle, each with:
- Unique field/wall/target color palette
- Different obstacle density
- Different target movement directions
- Increasing boss speed

### Screens

| Screen | Description |
|--------|-------------|
| KEITH | Title — cycling purple text |
| ADLER | Title — cycling purple text |
| PRESENTS | Title — gold text, asymmetric PF (no mirror) |
| CYLOID | Title — green text, asymmetric PF, tank flyby animation |
| Gameplay | Black field, colored obstacles, tank + targets + boss |
| Level Score | Score as digit sprites (P0/P1), victory jingle |
| Final Score | Score display after last death, sad melody |
| GAME OVER | Asymmetric PF text, subtle somber melody |

## Technical Architecture

### Hardware Usage

| TIA Object | Usage |
|------------|-------|
| Player 0 (P0) | Tank sprite (8 lines, 4 directional graphics) |
| Player 1 (P1) | Targets (flickered), boss, lives display (NUSIZ copies) |
| Missile 0 (M0) | Player bullet (4 clocks wide, 4 lines tall) |
| Playfield (PF) | Obstacles, walls, text screens, lives pips |
| Ball (BL) | Unused (removed — was boss bullet) |

### Frame Timing

```
VSYNC:    3 lines
VBLANK:  37 lines (TIM64T = 43)
Visible: 192 lines (8 border + 176 field + 8 border)
Overscan: 30 lines
Total:   262 lines (NTSC standard)
```

### Kernel Design

2-line kernel with cycle-tight budget:

- **Line 1** (max 70 cycles): Obstacle PF check + tank sprite (P0)
- **Line 2** (max 58 cycles): Target sprite (P1) + missile (M0)

Obstacle bands: `(scanline & $1F) >= $18` — 8-line bands every 32 lines.

### Frame Split

Game logic is split across two frames to fit in VBLANK:

- **Every frame**: Joystick input, fire button, flash/respawn, tank graphics, sound
- **Even frames**: Missile movement, hit detection (2 targets + boss)
- **Odd frames**: Wall collision, death timers, target movement, flicker select, boss logic, player collision

### Asymmetric Playfield

PRESENTS, CYLOID, and GAME OVER screens use mid-scanline PF register updates in reflect mode:

1. Write left-half PF0/PF1/PF2 at cycle ~7-21
2. Wait 10 NOPs (20 cycles) for beam to pass left PF2
3. Write right-half PF2/PF1/PF0 at cycle ~45-62

This gives 40 unique pixels per line — no mirroring or repeating.

### Flicker Multiplexing

P1 is shared between up to 5 targets and the boss:
- Targets cycle through FlickerIdx each odd frame
- Boss overrides P1 every other frame when active
- Dying targets/boss show explosion graphics (random XOR pattern)

### Collision Detection

| Collision | Method | Register |
|-----------|--------|----------|
| Tank vs walls | Hardware | CXP0FB bit 7 |
| Tank vs target/boss | Hardware | CXPPMM bit 7 |
| Missile vs walls | Hardware | CXM0FB bit 7 |
| Missile vs targets | Software | Distance check (12px box) |
| Missile vs boss | Software | Distance check (12px box) |

### Sound Design

| Sound | Channel | Waveform | Notes |
|-------|---------|----------|-------|
| Shoot | Ch0 | White noise (15) | Fast decay, dropping pitch |
| Hit target | Ch0 | Lead tone (12) | Medium decay |
| Wall hit | Ch0 | Low buzz (3) | Sad low pitch |
| Death | Ch0+Ch1 | Noise (8) + buzz (7) | Explosion + siren |
| Engine | Ch1 | Bass rumble (6) | While moving, vol 3 |
| Boss ping | Ch1 | Pure tone (4) | Every ~1 sec when boss active |
| Victory jingle | Ch1 | Warm lead (12) | 6-note ascending |
| Score melody | Ch1 | Warm lead (12) | 8-note descending |
| Game over | Ch1 | Warm lead (12) | 8-note somber |

### Memory Map

**RAM** ($80-$D8): ~88 bytes used, ~39 bytes free before stack

**ROM** ($F000-$FFFA): ~3700 bytes used, ~400 bytes free

### Sprite Data

4 tank directions (8 bytes each, contiguous for indexed access):
- TankUpGfx, TankRightGfx, TankDownGfx, TankLeftGfx

Target: 6-byte diamond shape (TargetGfx)

Digit sprites: 10 digits × 8 bytes (5px wide centered in 8px)

### Level Data Tables

| Table | Size | Description |
|-------|------|-------------|
| LvlField | 8 | Field background color per level |
| LvlWall | 8 | Wall/obstacle color per level |
| LvlTgt | 8 | Target color per level |
| LvlDirX | 8 | Target X movement direction |
| LvlDirY | 8 | Target Y movement direction |
| LvlObsMask | 8 | Obstacle density bitmask |
| SafeYTbl | 5 | Safe Y spawn positions for targets |

## Repository

- `game.asm` — Main game source (~2000 lines)
- `vcs.h` — TIA/RIOT register definitions
- `macro.h` — Standard macros (CLEAN_START, VERTICAL_SYNC, SLEEP)
- `Makefile` — Build automation
- `CHANGELOG.md` — Version history
