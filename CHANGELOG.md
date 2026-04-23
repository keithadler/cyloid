# Changelog - Cyloid

## v0.9 - April 23, 2026

### New Feature: Boss Flyby
- Player 2 boss randomly flies across the field every ~4-15 seconds
- Boss fires a Ball object toward the player's Y position
- Boss bullet kills the player on contact (Ball vs P0 collision)
- Shooting the boss awards 5 points
- Boss uses P1 on every 4th frame (targets get the other 3)
- Boss fire sound: menacing low buzz (AUDC=14)

### Gameplay
- 3 lives per game (was 2)
- Missiles stop when hitting playfield obstacles with a sad sound (CXM0FB collision)
- Black field background for cleaner look

### Fixes
- Boss ball tracks toward player Y (was always firing downward)
- Hit detection checks 2 targets per frame instead of 1 — much more reliable
- Replaced mod-3 division loop (up to 85 iterations!) with simple bitmask
- Boss logic gated to every 4th frame to prevent VBLANK overrun
- Fixed PRESENTS scanline count (was 200, now 192)
- Fixed game kernel top border (was 7 lines, now 8 — caused 191 visible lines)
- Ship on CYLOID screen disappears off right edge instead of wrapping
- All title screens handle their own VBLANK-off for correct frame timing
- 517 bytes ROM free

## v0.8 - April 23, 2026

### Critical Fix: Frame Stability
- **Root cause found**: page-crossing penalties on indexed loads (`ObsPF1,y`, `TankGfxBuf,y`) in the kernel pushed worst-case line 1 from 75 to 78 cycles, exceeding the 76-cycle scanline budget. This caused WSYNC slips when the tank was at certain Y positions.
- Sprite positioning moved into VBLANK period (was consuming 4 visible scanlines after VBLANK off)
- Obstacle check uses `cmp` instead of `sec/sbc` (saves 2 cycles)
- Removed dying target explosion graphics from kernel (saves 10+ cycles on line 2)
- Worst case now: line 1 = 70 cycles, line 2 = 58 cycles (both safe with page crosses)
- Game logic split across two frames: even frames handle missile/hits, odd frames handle death timers/movement/collision
- VBLANK timer restored to standard 43, overscan to 30 (3+37+192+30 = 262 exact)
- Exact 192 visible scanlines: 8 black top + 176 field + 8 black bottom

## v0.7 - April 23, 2026

### Title Sequence
- "PRESENTS" now displays as single non-mirrored word using asymmetric PF hack
- All 8 letters (PRESENTS) centered in 40 unique pixels, gold on black
- Removed old two-line PRES/ENTS split and DrawText2 subroutine

### Gameplay
- Obstacle density scales with level — level 0 has minimal obstacles, ramping to dense by level 5+
- Per-level density mask table controls PF bit patterns

### Fixes
- Bullet centered on tank (TankX+2 instead of +3 for 4-wide missile)
- Silenced all sounds when entering level-up screen — no more lingering chime behind victory jingle

### Audio
- Victory jingle on level-up score screen — 12-note ascending major arpeggio
- Somber melody on game-over score screen — 8-note descending minor scale

### Technical
- Removed DrawText2 subroutine (dead code after PRESENTS rewrite)
- Removed old PRES/ENTS mirrored PF data
- 1124 bytes ROM free

## v0.6 - April 23, 2026

### Fixes
- Fixed broken joystick controls — stray `lsr TempVar` shifted all direction bits, making tank drift right uncontrollably
- Restored safe `sec/sbc #1` for up/left movement to prevent underflow wrap
- Fixed top border green line — field colors now set before WSYNC transition
- Widened hit detection from 8×10 to 12×12 pixels to catch fast-moving missiles

### Performance (10 optimizations)
- Movement detection via single bitmask check instead of 4 separate `inc Moving`
- FlickerSel inlined — eliminated JSR/RTS overhead (12 cycles/frame)
- FlickerSel subroutine removed (60 bytes ROM freed)
- Move targets every 4th frame for all levels (removed level-based speed branching)
- Movement sound simplified — fixed frequency, silence uses A=0 from branch
- Hit check removed score cap (saves cycles per hit)
- Missile direction uses X register directly
- Removed missile X/Y clamping on fire
- Removed ChkHitX subroutine — hit detection fully inlined
- Simplified explosion to single-pass XOR

### Title
- Renamed game title from "CYCLOID" to "CYLOID" (6 letters, better centered)

## v0.5 - April 23, 2026

### Visual
- All borders now pure black (top, bottom, left, right)
- Removed score bar from top of game screen
- Obstacle bands offset 8 lines into field for better top-area navigation

### Bug Fixes (10)
1. Target spawn Y seed corruption — Y register was shared between position seed and Level index lookup, causing garbled positions after first target
2. Target X overflow — target at index 4 got X=153 (past boundary). Clamped to 130
3. Target Y in obstacle bands — spacing of 28 from Y=35 put targets at Y=63 and Y=91 (inside bands). Now uses safe Y lookup table: 40, 70, 105, 135, 165
4. Missile Y below field — firing at TankY=12 put missile at Y=15 (in black border). Clamped to minimum Y=10
5. Digit screen offsets corrupted — `inc TensOff`/`inc OnesOff` in renderer modified offsets, but BuildDigits only ran on first frame. Now rebuilds every frame
6. *(Verified correct — FlickerSel TgtLive values handled properly)*
7. Ball object (ENABL) not cleared in DoOverscan — could persist between screens
8. Melody timer wrap-around — after melody finished, `dec MelodyTimer` wrapped 0→255, running dead check 255 times. Set timer to 255 when done
9. NumTgts not cleared in InitGame — stale value from previous game could cause FlickerSel to read garbage between init and SetupLevel
10. Obstacle bands too close to top border — first band at scanline 24 was only 16 lines into field. Added 8-line offset so first band starts at scanline 32

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
