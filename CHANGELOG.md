# Changelog - Cyloid

## v0.4 - April 22, 2026

### Fixes
- Fixed CYCLOID title "L" rendering — proper 3px wide letter with full bottom bar
- Fixed asymmetric PF timing — added 2 extra NOPs to delay right-half PF2 write past cycle 44 (left PF2 latch point), fixing garbled C and L in center of screen
- Fixed screen height jitter during gameplay — VBLANK processing was overrunning timer on busy frames

### Performance
- VBLANK timer increased from 43 to 44 (64 more cycles headroom)
- Combined death timer + alive check into single loop pass (saves ~50 cycles)
- Simplified sound engine — universal decay replaces per-type branching (saves ~30 cycles)

## v0.3 - April 22, 2026

### Title Sequence
- New "CYCLOID" title screen using asymmetric playfield hack
- Mid-scanline PF register updates for 40 unique pixels (no mirroring/repeating)
- Cycling green/teal color, reflect-mode trick with timed NOP sled
- Sequence: KEITH → ADLER → PRESENTS → CYCLOID → Black → Game

### Performance (10 optimizations)
- SWCHA joystick port cached to RAM — eliminates 3 redundant I/O reads per frame
- Obstacle OFF path falls through to obsDone — saves 3 cycles on ~75% of kernel lines
- Score bar uses fixed gold color — removes 10-cycle per-line gradient calculation
- BufTankGfx consolidated from 4 separate loops to 1 computed-offset loop (saves ~40 bytes ROM)
- Target/death/check loops use `bcc` instead of `jmp` (saves 1 byte + 0-1 cycle each)
- BuildDigits called once per transition instead of every frame (saves ~7000 cycles per level-up)
- Sprite tables reordered to match TankDir values for indexed access

### Technical
- 972 bytes ROM free in 4KB cartridge
- Asymmetric PF data: 6 tables (left PF0/1/2 + right PF0/1/2) × 8 rows

## v0.2 - April 22, 2026

### Gameplay
- 2-5 random enemies per level (was fixed at 3)
- Enemy count varies each level based on pseudo-random seed
- Enemies now have death animations — explosion with random pixel noise and white flash
- Level only advances after the last enemy's death animation completes
- Score screen shown after game over before returning to title
- Flow: GAME OVER text → score display → title sequence
- Longer invincibility on respawn (45 frames) to prevent spawn deaths
- Death explosion plays at the location where the player died, not at spawn point
- Tank respawns at safe position (Y=170) only after explosion finishes

### Visuals
- Dying enemies flash white and show randomized pixel explosion (reuses player death effect)
- Score digits properly centered — single digit at X=76, double digits at X=65/85
- No leading zero on score (shows "3" not "03")
- Shared digit renderer for both level-up and post-game-over score screens

### Audio
- Redesigned all sound effects with proper TIA waveforms
- Shoot: white noise crack (AUDC=15) with fast decay and dropping pitch
- Hit: two-phase metallic ping (AUDC=12) transitioning to harsh crunch (AUDC=14)
- Death: dual-channel — heavy noise rumble (ch0) + sweeping industrial siren (ch1)
- Level up: ascending pure tone sweep
- Movement: subtle bass rumble (AUDC=6) at low volume
- Game over melody: haunting minor scale on warm lead tone (AUDC=12)
- Type-aware sound engine with per-effect decay curves

### Bug Fixes
- Fixed 30+ bugs across multiple audit passes including:
- Missile position underflow/overflow causing teleportation
- Direction negation using eor #$FE (broken for zero) replaced with proper 0-A negate
- Absolute value carry bug in all hit detection routines
- Sound never stopping (TIA write-only registers can't be read back)
- Tank/target spawning inside obstacle bands causing instant death loops
- Score uncapped past 40
- Ghost sprites bleeding into game over screen
- Melody delayed by uninitialized timer
- Collision latches not cleared on game init
- Movement sound overriding death siren
- BufTankGfx overwriting explosion graphics
- Score bar scaling (each line now = 8 points)
- Frame timing overruns from extra WSYNC lines
- Stale collision data causing death on first vulnerable frame after respawn

### Technical
- Target system restructured from 3 hardcoded targets to array-based (5 max)
- Parallel arrays: TgtAX, TgtAY, TgtALive, TgtADirX, TgtADirY
- TgtALive doubles as death timer (0=dead, 1=alive, 2-15=dying countdown)
- Removed dead SpawnTarget code (~150 bytes freed)
- 1.1KB ROM free in 4KB cartridge
- RAM verified safe: variables end at ~$D8, stack at $FF, 39+ byte gap

## v0.1 - April 22, 2026

Initial release.

### Game
- Tank shooter for Atari 2600 (4KB ROM, NTSC)
- Player controls a tank on a top-down field
- 3 enemy targets per level, flicker-multiplexed on Player 1
- Shoot all 3 to advance to the next level
- 8 levels with unique color palettes, obstacle layouts, and enemy movement patterns
- Random playfield obstacles generated per level
- Hardware collision detection: tank vs playfield walls and tank vs enemies
- 2 lives per game
- Score tracked across levels (max 40)

### Title Sequence
- "KEITH" screen with cycling purple text
- "ADLER" screen
- "PRESENTS" screen (two-line split: PRES / ENTS)
- Black transition screen
- Loops into gameplay after sequence

### Visuals
- Optimized 2-line kernel (~50 cycles worst case per scanline)
- Bright cyan tank sprite with 4 directional graphics
- Pulsing target glow effect
- Gradient gold score bar
- Explosion animation on death (randomized pixel noise + color shake)
- Per-level field/wall/target color themes

### Audio
- Channel 0: shoot, hit, death, level-up sounds with volume decay
- Channel 1: engine rumble on movement, descending death wail, 8-note game over melody

### Screens
- Score display between levels using Player 0/1 digit sprites (no leading zero)
- Centered "GAME OVER" text with color-cycling playfield font
- Clean black margins on all screens

### Technical
- DASM assembler, F3 output format
- Standard vcs.h / macro.h includes
- Proper VSYNC/VBLANK/overscan timing (262 lines NTSC)
- Hardware collision registers (CXP0FB, CXPPMM) for death detection
- Sound volume tracked in RAM (TIA write-only workaround)
- Pre-computed tank graphics buffer during VBLANK
- Obstacle bands via bitmask: `(scanline & $1F) >= $18`
