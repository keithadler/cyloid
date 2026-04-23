; =============================================================================
; game.asm - Cyloid Tank Game - Atari 2600 (4KB NTSC)
; =============================================================================
;
; A tank shooter where the player navigates obstacle-filled arenas,
; destroys targets to advance levels, and survives homing boss attacks.
;
; HARDWARE USAGE:
;   P0 (Player 0)  = Tank sprite (8 lines, 4 directions)
;   P1 (Player 1)  = Targets (flicker-multiplexed) + Boss (yellow)
;   M0 (Missile 0) = Player bullet (4 clocks wide, 6 lines tall)
;   PF (Playfield)  = Obstacles, walls, title text, lives pips
;   Ball            = Unused
;
; FRAME TIMING (NTSC 262 lines):
;   VSYNC:    3 lines
;   VBLANK:  37 lines (TIM64T=43, sprite positioning here)
;   Visible: 192 lines (8 border + 176 field + 8 border)
;   Overscan: 30 lines
;
; KERNEL: 2-line design
;   Line 1: Obstacle PF + Tank P0 (max 70 cycles)
;   Line 2: Target P1 + Missile M0 (max 58 cycles)
;
; GAME LOGIC: Split across two frames to fit in VBLANK
;   Every frame: Joystick, fire, flash/respawn, tank gfx, sound
;   Even frames: Missile movement, hit detection (2 targets + boss)
;   Odd frames:  Wall collision, death timers, movement, flicker, boss, collision
;
; BUILD: dasm game.asm -f3 -ogame.bin
; =============================================================================

            processor 6502
            include "vcs.h"
            include "macro.h"

;===============================================================================
; Game State Constants
;===============================================================================

MODE_TITLE     = 0          ; Title sequence (KEITH/ADLER/PRESENTS/CYLOID/BLACK)
MODE_PLAY      = 1          ; Active gameplay
MODE_OVER      = 2          ; "GAME OVER" text display
MODE_LVLUP     = 3          ; Between-level score display
MODE_SCORE     = 4          ; Final score display after last death

TITLE_KEITH    = 0          ; Title sub-states (sequential)
TITLE_ADLER    = 1
TITLE_PRESENTS = 2
TITLE_CYLOID   = 3
TITLE_BLACK    = 4
NUM_TITLE      = 5          ; Total title screens

TANK_H         = 8          ; Tank sprite height in scanlines
MAX_TGTS       = 5          ; Maximum enemies per level

;===============================================================================
; RAM Variables ($80-$D8, ~88 bytes used)
; Stack grows down from $FF, ~39 bytes free gap
;===============================================================================

            SEG.U Variables
            ORG $80

; --- Core State ---
GameMode    ds 1            ; Current game mode (MODE_*)
SubState    ds 1            ; Title: sub-screen index. Play: 0=waiting, 1=started
StateTimer  ds 1            ; Countdown timer for timed states (frames)
FrameCount  ds 1            ; Global frame counter (wraps at 256)
TempVar     ds 1            ; Scratch variable (cached SWCHA, alive count, etc.)

; --- Playfield Text Buffers (used by title screen renderers) ---
PFData0     ds 8            ; PF0 data for 8 text rows
PFData1     ds 8            ; PF1 data for 8 text rows
PFData2     ds 8            ; PF2 data for 8 text rows

; --- Player Tank (P0) ---
TankX       ds 1            ; Horizontal position (8-148)
TankY       ds 1            ; Vertical position / scanline (12-175)
TankDir     ds 1            ; Direction: 0=up, 1=right, 2=down, 3=left

; --- Player Missile (M0) ---
MissileX    ds 1            ; Horizontal position
MissileY    ds 1            ; Vertical position / scanline
MissileDir  ds 1            ; Direction (same encoding as TankDir)
MissileOn   ds 1            ; 0=inactive, 2=active (2 = ENAM0 enable value)

; --- Flicker-Selected Target (passed to kernel each frame) ---
TgtX        ds 1            ; X position of target to draw this frame
TgtY        ds 1            ; Y position of target to draw this frame
TgtLive     ds 1            ; 0=none, 1=alive, 2-15=dying, 50=boss alive

; --- Target Arrays (up to 5 enemies) ---
TgtAX       ds MAX_TGTS     ; X positions
TgtAY       ds MAX_TGTS     ; Y positions
TgtALive    ds MAX_TGTS     ; 0=dead, 1=alive, 2-15=dying (death timer countdown)
TgtADirX    ds MAX_TGTS     ; X direction: 0=none, 1=right, $FF=left
TgtADirY    ds MAX_TGTS     ; Y direction: 0=none, 1=down, $FF=up
NumTgts     ds 1            ; Number of targets this level (2-5)
FlickerIdx  ds 1            ; Which target P1 draws this frame (cycles 0 to NumTgts-1)

; --- Scoring & Lives ---
Score       ds 1            ; Player score (0-99)
ButtonPrev  ds 1            ; Previous frame's INPT4 (for edge detection)
SndVol      ds 1            ; Channel 0 volume (tracked in RAM, TIA is write-only)
Lives       ds 1            ; Remaining lives (0-3)
HitFlash    ds 1            ; Death flash timer (45=just died, counts down to 0)
Level       ds 1            ; Current level (0-7, wraps)
KillCount   ds 1            ; Kills this level (unused after target array rewrite)

; --- Level Appearance ---
FieldColor  ds 1            ; Background color (from LvlField table)
WallColor   ds 1            ; Obstacle/wall color (from LvlWall table)
TgtColor    ds 1            ; Target color (from LvlTgt table)

; --- Pre-computed Kernel Data ---
TankGfxBuf  ds 8            ; Tank sprite for current direction (copied during VBLANK)
ObsPF1      ds 4            ; PF1 obstacle pattern for 4 horizontal bands
ObsPF2      ds 4            ; PF2 obstacle pattern for 4 horizontal bands

; --- Audio & UI ---
Moving      ds 1            ; Nonzero if joystick pressed this frame
MelodyIdx   ds 1            ; Current note index for melody playback
MelodyTimer ds 1            ; Frames until next melody note
TensOff     ds 1            ; Tens digit offset into DigitSprites ($FF = no tens)
OnesOff     ds 1            ; Ones digit offset into DigitSprites
SndType     ds 1            ; Current ch0 sound type (0=none, 1=shoot, 2=hit, 3=death)
RandSeed    ds 1            ; LFSR pseudo-random seed (must be non-zero)

; --- Boss (Player 2 Homing Attacker) ---
BossX       ds 1            ; Horizontal position (0-155)
BossY       ds 1            ; Vertical position (10-175)
BossActive  ds 1            ; 0=inactive, 1=alive/homing, 2-15=dying (death timer)
BossTimer   ds 1            ; Countdown to next boss appearance (frames)
Streak      ds 1            ; #8: Consecutive hit counter (0-5)
MoveTimer   ds 1            ; #6: Frames joystick held (for acceleration)

;===============================================================================
; ROM Code ($F000-$FFFA)
; Organized as:
;   Reset + Main Loop
;   Title Logic
;   InitGame + SetupLevel + GenObstacles
;   GameLogic (frame-split: even=missile/hits, odd=movement/collision)
;   Random + MoveTargets
;   LvlUpLogic + ScoreLogic + BuildDigits + OverLogic
;   WaitDraw + DrawTitle dispatch
;   DrawGame kernel (2-line, cycle-tight)
;   DrawDigitScreen (score display with P0/P1 digit sprites)
;   DrawOver (asymmetric PF "GAME OVER")
;   DoOverscan
;   Title Renderers (Keith, Adler, Presents, Cyloid, Black)
;   Sprite Data + Level Tables + Font Data
;   Vectors ($FFFA)
;===============================================================================

            SEG Code
            ORG $F000

Reset
            CLEAN_START
            lda #MODE_TITLE
            sta GameMode
            lda #TITLE_KEITH
            sta SubState
            lda #180
            sta StateTimer

;===============================================================================
; MAIN LOOP
;===============================================================================
MainLoop
            ; === VSYNC: 3 lines ===
            lda #2
            sta VSYNC
            sta WSYNC
            sta WSYNC
            sta WSYNC
            lda #0
            sta VSYNC

            ; === VBLANK: 37 lines ===
            lda #2
            sta VBLANK
            lda #43             ; 43*64 = 2752 cycles = ~36.2 lines
            sta TIM64T
            inc FrameCount

            lda GameMode
            cmp #MODE_PLAY
            beq .play
            cmp #MODE_OVER
            beq .over
            cmp #MODE_LVLUP
            beq .lvlup
            cmp #MODE_SCORE
            beq .score
            jmp TitleLogic
.play       jmp GameLogic
.over       jmp OverLogic
.lvlup      jmp LvlUpLogic
.score      jmp ScoreLogic

;===============================================================================
; TITLE
;===============================================================================
TitleLogic SUBROUTINE
            dec StateTimer
            bne .done
            ldx SubState
            inx
            cpx #NUM_TITLE
            bcc .next
            lda #MODE_PLAY
            sta GameMode
            jsr InitGame
            jmp .done
.next       stx SubState
            lda TitleTimers,x
            sta StateTimer
.done       jmp WaitDraw

TitleTimers .byte 180,150,150,180,90

;===============================================================================
; INIT
;===============================================================================
InitGame SUBROUTINE
            lda #78
            sta TankX
            lda #170
            sta TankY
            lda #0
            sta TankDir
            sta MissileOn
            sta Score
            sta Level
            sta KillCount
            sta FlickerIdx
            sta HitFlash
            sta SndVol
            sta AUDV0
            sta AUDV1
            sta Moving
            sta MelodyIdx
            sta MelodyTimer
            sta TgtX
            sta TgtY
            sta TgtLive
            sta SndType
            sta NumTgts
            sta BossActive
            sta Streak
            sta MoveTimer
            sta SubState
            lda FrameCount      ; #6: seed LFSR from frame count (varies each game)
            ora #1              ; ensure non-zero
            sta RandSeed
            lda #120
            sta BossTimer
            lda #3
            sta Lives
            sta CXCLR
            jsr SetupLevel
            rts

SetupLevel SUBROUTINE
            ldx Level
            lda LvlField,x
            sta FieldColor
            lda LvlWall,x
            sta WallColor
            lda LvlTgt,x
            sta TgtColor
            lda #0
            sta KillCount

            ; Random enemy count: 2-5 based on level + frame
            lda FrameCount
            eor Level
            and #$03            ; 0-3
            clc
            adc #2              ; 2-5
            sta NumTgts

            ; Spawn targets at safe, spread positions
            ldx #0
.spawnLoop
            cpx NumTgts
            bcs .spawnDone
            ; X position: spread across field, clamped
            txa
            asl
            asl
            asl
            asl
            asl                 ; X * 32
            clc
            adc #20
            cmp #130            ; Bug 2: clamp X
            bcc .xSafe
            lda #100
.xSafe      sta TgtAX,x
            ; Y position: safe zones avoiding obstacle bands
            ; Bands at (line & $1F) >= $18: 24-31, 56-63, 88-95, 120-127, 152-159
            ; Safe: 35-55, 65-87, 97-119, 129-151, 161-175
            ; Bug 3: use lookup table for safe Y positions
            lda SafeYTbl,x
            sta TgtAY,x
            ; Alive
            lda #1
            sta TgtALive,x
            ; Direction from level table
            ldy Level
            lda LvlDirX,y
            sta TgtADirX,x
            ; Alternate direction for odd targets
            txa
            and #1
            beq .noFlip
            lda #0
            sec
            sbc TgtADirX,x
            sta TgtADirX,x
.noFlip
            ldy Level
            lda LvlDirY,y
            sta TgtADirY,x
            txa
            and #1
            beq .noFlipY
            lda #0
            sec
            sbc TgtADirY,x
            sta TgtADirY,x
.noFlipY
            inx
            jmp .spawnLoop
.spawnDone
            ; Clear remaining slots
.clearLoop  cpx #MAX_TGTS
            bcs .clearDone
            lda #0
            sta TgtALive,x
            inx
            jmp .clearLoop
.clearDone
            jsr GenObstacles
            rts

GenObstacles SUBROUTINE
            ; Density scales with level via mask table
            ldy Level
            lda LvlObsMask,y   ; density mask for this level
            sta TempVar         ; store mask

            lda Level
            asl
            asl
            asl
            clc
            adc FrameCount
            tax
            ; Band 0
            txa
            asl
            eor #$A5
            and TempVar
            sta ObsPF1
            txa
            lsr
            eor #$5A
            and TempVar
            sta ObsPF2
            ; Band 1
            txa
            clc
            adc #$37
            eor #$C3
            and TempVar
            sta ObsPF1+1
            txa
            clc
            adc #$91
            eor #$3C
            and TempVar
            sta ObsPF2+1
            ; Band 2
            txa
            clc
            adc #$6B
            eor #$55
            and TempVar
            sta ObsPF1+2
            txa
            clc
            adc #$D2
            eor #$AA
            and TempVar
            sta ObsPF2+2
            ; Band 3
            txa
            clc
            adc #$1F
            eor #$69
            and TempVar
            sta ObsPF1+3
            txa
            clc
            adc #$E4
            eor #$96
            and TempVar
            sta ObsPF2+3
            rts

;===============================================================================
; GAME LOGIC
;===============================================================================
GameLogic SUBROUTINE
            ; Wait for player to move before starting level 1
            lda SubState
            bne .gameStarted
            ; Check if any direction pressed
            lda SWCHA
            and #%11110000
            cmp #%11110000
            beq .waitForMove    ; no input — skip all logic, just draw
            ; Player moved! Start the game
            lda #1
            sta SubState
            ; Fall through to gameStarted with this frame's input
.waitForMove
            jmp WaitDraw        ; draw the field but don't run logic

.gameStarted
            ; === EVERY FRAME: joystick + fire ===
            lda #0
            sta Moving
            lda SWCHA
            sta TempVar

            lda TempVar
            and #%00010000
            bne .noU
            lda #0
            sta TankDir
            lda TankY
            sec
            sbc #1
            cmp #12
            bcs .upOk
            lda #12
.upOk       sta TankY
.noU
            lda TempVar
            and #%00100000
            bne .noD
            lda #2
            sta TankDir
            inc TankY
            lda TankY
            cmp #175
            bcc .noD
            lda #175
            sta TankY
.noD
            lda TempVar
            and #%01000000
            bne .noL
            lda #3
            sta TankDir
            lda TankX
            sec
            sbc #1
            cmp #8
            bcs .leftOk
            lda #8
.leftOk     sta TankX
.noL
            lda TempVar
            and #%10000000
            bne .noR
            lda #1
            sta TankDir
            inc TankX
            lda TankX
            cmp #148
            bcc .noR
            lda #148
            sta TankX
.noR
            lda TempVar
            and #%11110000
            cmp #%11110000
            beq .notMoving
            lda #1
            sta Moving
.notMoving

            lda INPT4
            bmi .noF
            lda ButtonPrev
            bpl .noF
            lda MissileOn
            bne .noF
            lda #2
            sta MissileOn
            lda TankX
            clc
            adc #2
            sta MissileX
            lda TankY
            clc
            adc #2
            sta MissileY
            lda TankDir
            sta MissileDir
            lda #15
            sta AUDC0
            lda #12
            sta SndVol
            sta AUDV0
            lda #3
            sta AUDF0
            lda #1
            sta SndType
.noF
            lda INPT4
            sta ButtonPrev

            ; === FRAME SPLIT: alternate heavy work ===
            lda FrameCount
            and #1
            beq .evenFrame
            jmp .oddFrame

            ; === EVEN FRAME: missile movement only ===
.evenFrame
            lda MissileOn
            bne .mGo
            jmp .frameDone

.mGo        ldx MissileDir
            cpx #0
            bne .md1
            lda MissileY
            sec
            sbc #4
            bcc .mKill
            sta MissileY
            cmp #8
            bcs .mHit
            jmp .mKill
.md1        cpx #2
            bne .md2
            lda MissileY
            clc
            adc #4
            sta MissileY
            cmp #180
            bcc .mHit
            jmp .mKill
.md2        cpx #3
            bne .md3
            lda MissileX
            sec
            sbc #4
            bcc .mKill
            sta MissileX
            cmp #8
            bcs .mHit
            jmp .mKill
.md3        lda MissileX
            clc
            adc #4
            sta MissileX
            cmp #150
            bcc .mHit
.mKill      lda #0
            sta MissileOn
            sta Streak          ; #8: reset streak on miss
            jmp .frameDone

.mHit       ; Check 2 targets per frame (rotate)
            lda FrameCount
            lsr
            and #$07
            cmp NumTgts
            bcc .idx1ok
            lda #0
.idx1ok     tax
            ; Target 1
            lda TgtALive,x
            cmp #1
            bne .try2nd
            lda MissileY
            sec
            sbc TgtAY,x
            bcs .hy1
            eor #$FF
            adc #1
.hy1        cmp #12
            bcs .try2nd
            lda MissileX
            sec
            sbc TgtAX,x
            bcs .hx1
            eor #$FF
            adc #1
.hx1        cmp #12
            bcs .try2nd
            jmp .hitTarget
            ; Target 2
.try2nd     inx
            cpx NumTgts
            bcc .idx2ok
            ldx #0
.idx2ok     lda TgtALive,x
            cmp #1
            bne .hitMiss
            lda MissileY
            sec
            sbc TgtAY,x
            bcs .hy2
            eor #$FF
            adc #1
.hy2        cmp #12
            bcs .hitMiss
            lda MissileX
            sec
            sbc TgtAX,x
            bcs .hx2
            eor #$FF
            adc #1
.hx2        cmp #12
            bcs .hitMiss
.hitTarget  ; HIT — #8: streak scoring
            lda #15
            sta TgtALive,x
            lda #0
            sta MissileOn
            ; Add streak bonus (1 + min(streak, 4))
            inc Streak
            lda Streak
            cmp #5
            bcc .strkOk
            lda #5
.strkOk     clc
            adc Score
            sta Score
            lda #12
            sta AUDC0
            lda #15
            sta SndVol
            sta AUDV0
            lda #4
            sta AUDF0
            lda #2
            sta SndType
            jmp .frameDone
.hitMiss
            ; Boss hit check
            lda BossActive
            bne .bossHitChk
            jmp .frameDone
.bossHitChk
            lda MissileY
            sec
            sbc BossY
            bcs .bhy
            eor #$FF
            adc #1
.bhy        cmp #12
            bcc .bhyOk
            jmp .frameDone
.bhyOk
            lda MissileX
            sec
            sbc BossX
            bcs .bhx
            eor #$FF
            adc #1
.bhx        cmp #12
            bcc .bhxOk
            jmp .frameDone
.bhxOk
            ; Boss hit — no points, just destroy it
            lda #15
            sta BossActive      ; >1 = dying
            lda #0
            sta MissileOn
            sta ENABL
            lda #12
            sta AUDC0
            lda #15
            sta SndVol
            sta AUDV0
            lda #2
            sta AUDF0
            lda #2
            sta SndType
            jmp .frameDone

            ; === ODD FRAME: wall collision + death timers + move + flicker + collision ===
.oddFrame
            ; Check missile vs wall (moved from even frame to save cycles)
            lda MissileOn
            beq .noWall
            lda CXM0FB
            bpl .noWall
            lda #0
            sta MissileOn
            sta Streak          ; #8: reset streak on wall hit
            lda #3
            sta AUDC0
            lda #6
            sta SndVol
            sta AUDV0
            lda #20
            sta AUDF0
            lda #1
            sta SndType
.noWall

            ; Death timers
            ldx #0
            ldy #0
            cpx NumTgts         ; Bug 8: check before first iteration
            bcs .deathDone
.deathLoop  lda TgtALive,x
            beq .deathNext
            cmp #2
            bcc .countAlive
            sec
            sbc #1
            sta TgtALive,x
            cmp #1
            bne .countAlive
            lda #0
            sta TgtALive,x
            jmp .deathNext
.countAlive iny
.deathNext  inx
            cpx NumTgts
            bcc .deathLoop
.deathDone
            cpy #0
            bne .noLvlAdv
            ; #9: Flash screen white on level complete
            lda #$0E
            sta COLUBK
            lda #MODE_LVLUP
            sta GameMode
            lda #120
            sta StateTimer
            lda #0
            sta SndVol
            sta SndType
            sta AUDV0
            sta AUDV1
            jmp .frameDone
.noLvlAdv

            ; Move targets — faster on higher levels
            lda Level
            cmp #6
            bcs .doMv           ; level 6+: every odd frame
            cmp #3
            bcs .moveFast       ; level 3-5: every 2nd odd frame
            ; Level 0-2: every 4th odd frame
            lda FrameCount
            and #%00000110
            bne .skipMv
            jmp .doMv
.moveFast   lda FrameCount
            and #%00000010
            bne .skipMv
.doMv       jsr MoveTargets
.skipMv

            ; Flicker select (inline)
            lda NumTgts         ; Bug 5: guard for 0 targets
            beq .fNone
            ldx FlickerIdx
            inx
            cpx NumTgts
            bcc .fOk
            ldx #0
.fOk        stx FlickerIdx
            ldy NumTgts
.fTry       lda TgtALive,x
            bne .fFound
            inx
            cpx NumTgts
            bcc .fTnw
            ldx #0
.fTnw       dey
            bne .fTry
            lda #0
            sta TgtLive
            jmp .fDone
.fNone      lda #0
            sta TgtLive
            jmp .fDone
.fFound     sta TgtLive
            lda TgtAX,x
            sta TgtX
            lda TgtAY,x
            sta TgtY
.fDone

            ; Boss timer decrements every odd frame (not gated)
            lda BossActive
            cmp #2
            bcc .bossNotDying
            jmp .bossSkipLogic  ; dying, skip
.bossNotDying
            cmp #1
            beq .bossLogicGate
            dec BossTimer
            bne .bossLogicGate
            ; Spawn boss from random edge
            lda #1
            sta BossActive
            ; Random: spawn from left or right
            lda FrameCount
            and #1
            beq .spawnLeft
            lda #155            ; spawn from right
            jmp .spawnXset
.spawnLeft  lda #5              ; spawn from left
.spawnXset  sta BossX
            jsr Random          ; #6: use LFSR for boss Y
            and #$7F
            clc
            adc #30
            cmp #150
            bcc .byOk
            lda #80
.byOk       sta BossY
            jmp .bossSkipLogic

.bossLogicGate
            lda FrameCount
            and #%00000110
            beq .doBossLogic
            jmp .bossSkipLogic
.doBossLogic
            lda BossActive
            cmp #1
            beq .bossMove
            jmp .bossEnd

.bossMove
            ; Home toward player X (speed scales with level)
            lda BossX
            cmp TankX
            beq .bmx
            bcc .bRight
            dec BossX
            dec BossX
            lda Level
            cmp #3
            bcc .bmx
            dec BossX           ; faster at level 3+
            cmp #6
            bcc .bmx
            dec BossX           ; even faster at level 6+
            jmp .bmx
.bRight     inc BossX
            inc BossX
            lda Level
            cmp #3
            bcc .bmx
            inc BossX
            cmp #6
            bcc .bmx
            inc BossX
.bmx
            ; Clamp boss X to screen
            lda BossX
            cmp #160
            bcc .bxOk
            lda #155
            sta BossX
.bxOk
            ; Home toward player Y (same speed scaling)
            lda BossY
            cmp TankY
            beq .bossEnd
            bcc .bDown
            dec BossY
            dec BossY
            lda Level
            cmp #3
            bcc .bossEnd
            dec BossY
            cmp #6
            bcc .bossEnd
            dec BossY
            jmp .bossEnd
.bDown      inc BossY
            inc BossY
            lda Level
            cmp #3
            bcc .bossEnd
            inc BossY
            cmp #6
            bcc .bossEnd
            inc BossY

.bossEnd
            ; Clamp boss Y
            lda BossY
            cmp #180
            bcc .byClamp
            lda #175
            sta BossY
.byClamp
            lda BossY
            cmp #10
            bcs .byClamp2
            lda #10
            sta BossY
.byClamp2
.bossSkipLogic

            ; Collision
            lda HitFlash
            bne .skipC
            lda CXP0FB
            bmi .doDeath        ; P0 vs PF
            lda CXPPMM          ; P0 vs P1 (boss or target contact)
            bpl .skipC
.doDeath
            dec Lives
            lda Lives
            bpl .livesOk
            lda #0
            sta Lives
.livesOk
            lda #45
            sta HitFlash
            lda #8
            sta AUDC0
            lda #15
            sta SndVol
            sta AUDV0
            lda #5
            sta AUDF0
            lda #3
            sta SndType
            lda #7
            sta AUDC1
            lda #15
            sta AUDV1
            lda #2
            sta AUDF1
            ; Reset boss on player death so it doesn't camp spawn
            lda #0
            sta BossActive
            lda FrameCount
            ora #$78
            sta BossTimer       ; respawn boss later
.skipC      sta CXCLR

            ; === EVERY FRAME (after split): boss display + flash + gfx + sound ===
.frameDone
            ; Show boss on P1 every other frame
            lda BossActive
            beq .noBossFrame
            cmp #1
            beq .bossAlive
            ; Boss dying — decrement timer
            sec
            sbc #1
            sta BossActive
            cmp #1
            bne .bossShow
            ; Death animation done
            lda #0
            sta BossActive
            lda FrameCount
            ora #$78
            sta BossTimer       ; reset timer for next appearance
            jmp .noBossFrame
.bossShow   ; Show explosion at boss position
            lda FrameCount
            and #$01
            bne .noBossFrame
            lda BossX
            sta TgtX
            lda BossY
            sta TgtY
            lda #2              ; dying = explosion graphics in kernel
            sta TgtLive
            jmp .noBossFrame
.bossAlive
            lda FrameCount
            and #$01
            bne .noBossFrame
            lda BossX
            sta TgtX
            lda BossY
            sta TgtY
            lda #50             ; boss alive marker
            sta TgtLive
.noBossFrame

            ; Skip flash logic if no flash
            lda HitFlash
            beq .noFl
            dec HitFlash
            bne .flashCont
            ; Respawn
            lda #78
            sta TankX
            lda #170
            sta TankY
            lda #0
            sta MissileOn       ; Bug 7: clear missile on respawn
            sta AUDV1
            lda Lives
            bne .noFl
            lda #0
            sta SndVol
            sta AUDV0
            sta BossActive      ; Bug 10: clear boss on game end
            sta ENABL
            lda #MODE_SCORE
            sta GameMode
            lda #150
            sta StateTimer
            lda #0
            sta MelodyIdx
            lda #1
            sta MelodyTimer
            jmp .noFl
.flashCont
            lda HitFlash
            lsr
            sta AUDF1
            lsr
            sta AUDV1
.noFl
            ; OPT 1+3: Tank gfx — inline BufTankGfx, skip if flashing
            lda HitFlash
            bne .doExp
            ; Inline BufTankGfx (saves 12 cycle JSR/RTS)
            lda TankDir
            asl
            asl
            asl
            tay
            ldx #0
.bufLp      lda TankUpGfx,y
            sta TankGfxBuf,x
            iny
            inx
            cpx #8
            bne .bufLp
            jmp .gfxDone
.doExp      ; #10: Death debris — explosion on both P0 and P1
            lda FrameCount
            eor HitFlash
            sta TankGfxBuf
            sta TankGfxBuf+2
            sta TankGfxBuf+4
            sta TankGfxBuf+6
            eor #$FF
            sta TankGfxBuf+1
            sta TankGfxBuf+3
            sta TankGfxBuf+5
            sta TankGfxBuf+7
.gfxDone

            ; OPT 7: Sound decay — minimal check
            lda SndVol
            beq .nsd
            lda FrameCount
            lsr                 ; carry = bit 0
            bcs .nsd            ; skip odd frames
            dec SndVol
            lda SndVol
            sta AUDV0
            bne .nsd
            sta SndType         ; clear type when vol hits 0
.nsd
            ; Channel 1: boss alarm > movement sound > silence
            lda HitFlash
            bne .moveDone
            ; Boss alarm takes priority
            lda BossActive
            cmp #1
            bne .noAlarm
            ; Occasional boss ping: short blip every ~1 second
            lda FrameCount
            and #%00111111      ; every 64 frames (~1 sec)
            bne .noAlarm        ; silent most of the time
            lda #4              ; pure tone
            sta AUDC1
            lda #3              ; quiet
            sta AUDV1
            lda #6              ; mid-high pitch blip
            sta AUDF1
            jmp .moveDone
.noAlarm
            lda Moving
            beq .silence
            lda #6
            sta AUDC1
            lda #3
            sta AUDV1
            lda #30
            sta AUDF1
            jmp .moveDone
.silence    sta AUDV1
.moveDone

            ; OPT 5: Win check only on even frames (score only changes on even)
            lda FrameCount
            lsr
            bcs .noWin
            lda Score
            cmp #99             ; win at 99 points
            bcc .noWin
            lda #0
            sta SndVol
            sta AUDV0
            sta AUDV1
            sta BossActive
            sta ENABL
            lda #MODE_SCORE
            sta GameMode
            lda #150
            sta StateTimer
            lda #0
            sta MelodyIdx
            lda #1
            sta MelodyTimer
.noWin      jmp WaitDraw

; #6: LFSR pseudo-random number generator
; Call: jsr Random. Returns random byte in A. Updates RandSeed.
Random SUBROUTINE
            lda RandSeed
            lsr
            bcc .noTap
            eor #$B4            ; taps for maximal 8-bit LFSR
.noTap      sta RandSeed
            rts

MoveTargets SUBROUTINE
            ; #8: Count alive targets for speed-up
            ldy #0              ; alive count
            ldx #0
.countLp    cpx NumTgts
            bcs .countDn
            lda TgtALive,x
            cmp #1
            bne .countNx
            iny
.countNx    inx
            bne .countLp
.countDn    ; Y = alive count. Store for speed check
            sty TempVar         ; reuse TempVar for alive count

            ldx #0
.loop       cpx NumTgts
            bcs .done
            lda TgtALive,x
            cmp #1
            bne .next
            ; Move X
            lda TgtADirX,x
            beq .my
            cmp #1
            bne .ml
            inc TgtAX,x
            ; #8: extra move if 1-2 targets left
            lda TempVar
            cmp #3
            bcs .mxrOk
            inc TgtAX,x
.mxrOk      lda TgtAX,x
            cmp #135
            bcc .my
            lda #$FF
            sta TgtADirX,x
            jmp .my
.ml         dec TgtAX,x
            lda TempVar
            cmp #3
            bcs .mxlOk
            dec TgtAX,x
.mxlOk      lda TgtAX,x
            cmp #12
            bcs .my
            lda #1
            sta TgtADirX,x
.my         ; Move Y
            lda TgtADirY,x
            beq .next
            cmp #1
            bne .mu
            inc TgtAY,x
            lda TempVar
            cmp #3
            bcs .mydOk
            inc TgtAY,x
.mydOk      lda TgtAY,x
            cmp #155
            bcc .next
            lda #$FF
            sta TgtADirY,x
            jmp .next
.mu         dec TgtAY,x
            lda TempVar
            cmp #3
            bcs .myuOk
            dec TgtAY,x
.myuOk      lda TgtAY,x
            cmp #15
            bcs .next
            lda #1
            sta TgtADirY,x
.next       inx
            cpx NumTgts         ; Opt 6: use bcc instead of jmp
            bcc .loop
.done       rts

LvlUpLogic SUBROUTINE
            dec StateTimer
            bne .wait
            lda #0
            sta SndVol
            sta AUDV0
            sta AUDV1
            lda Level
            clc
            adc #1
            and #7
            sta Level
            jsr SetupLevel
            ; Reset tank to safe spawn + clear collisions
            lda #78
            sta TankX
            lda #170
            sta TankY
            lda #0
            sta MissileOn
            sta HitFlash
            sta BossActive      ; Bug 6: clear boss on level change
            sta ENABL
            sta CXCLR
            lda #MODE_PLAY
            sta GameMode
            jmp WaitDraw
.wait       ; Build digits on first frame + init jingle
            lda StateTimer
            cmp #119
            bne .playJingle
            jsr BuildDigits
            lda #0
            sta MelodyIdx
            lda #1
            sta MelodyTimer
.playJingle
            ; Victory jingle on ch1
            dec MelodyTimer
            bne .skip
            ldx MelodyIdx
            cpx #6              ; 6 notes
            bcs .jingleDone
            lda VictoryNotes,x
            sta AUDF1
            lda #12             ; warm lead tone
            sta AUDC1
            lda VictoryVols,x
            sta AUDV1
            lda #15             ; slower, more pleasant
            sta MelodyTimer
            inc MelodyIdx
            jmp .skip
.jingleDone lda #0
            sta AUDV1
.skip       jmp WaitDraw

ScoreLogic SUBROUTINE
            dec StateTimer
            bne .wait
            ; Score done → go to GAME OVER screen
            lda #0
            sta AUDV0
            sta AUDV1
            lda #MODE_OVER
            sta GameMode
            lda #180
            sta StateTimer
            lda #0
            sta MelodyIdx
            lda #1
            sta MelodyTimer
            jmp WaitDraw
.wait       lda StateTimer
            cmp #149
            bne .playJingle
            jsr BuildDigits
            lda #0
            sta MelodyIdx
            lda #1
            sta MelodyTimer
.playJingle
            ; Sad melody on score screen (descending)
            dec MelodyTimer
            bne .skip
            ldx MelodyIdx
            cpx #8
            bcs .melDone
            lda MelodyNotes,x
            sta AUDF1
            lda #12
            sta AUDC1
            lda MelodyVols,x
            sta AUDV1
            lda #18
            sta MelodyTimer
            inc MelodyIdx
            jmp .skip
.melDone    lda #0
            sta AUDV1
.skip       jmp WaitDraw

BuildDigits SUBROUTINE
            lda Score
            ldx #0
.div10      cmp #10
            bcc .divDone
            sbc #10
            inx
            jmp .div10
.divDone    asl
            asl
            asl
            sta OnesOff
            cpx #0
            bne .hasTens
            lda #$FF
            sta TensOff
            rts
.hasTens    txa
            asl
            asl
            asl
            sta TensOff
            rts

OverLogic SUBROUTINE
            dec StateTimer
            bne .melody
            ; Game Over done → return to title
            lda #0
            sta SndVol
            sta AUDV0
            sta AUDV1
            lda #MODE_TITLE
            sta GameMode
            lda #TITLE_KEITH
            sta SubState
            lda #180
            sta StateTimer
            jmp WaitDraw
.melody
            ; Dramatic game over melody (different from score screen)
            dec MelodyTimer
            bne .w
            ldx MelodyIdx
            cpx #8
            bcs .melDone
            lda GONotes,x
            sta AUDF1
            lda #12             ; warm lead tone — softer
            sta AUDC1
            lda GOVols,x
            sta AUDV1
            lda #30             ; slower tempo
            sta MelodyTimer
            inc MelodyIdx
            jmp .w
.melDone    lda #0
            sta AUDV1
            lda #255
            sta MelodyTimer
.w          jmp WaitDraw

;===============================================================================
; WAIT + DISPATCH
;===============================================================================
WaitDraw SUBROUTINE
            lda INTIM
            bne WaitDraw
            ; Don't turn off VBLANK here - let each renderer do it
            ; after positioning sprites (keeps positioning invisible)
            lda GameMode
            cmp #MODE_PLAY
            beq .g
            cmp #MODE_OVER
            beq .o
            cmp #MODE_LVLUP
            beq .lv
            cmp #MODE_SCORE
            beq .sc
            ; Non-game screens: check if CYLOID (needs positioning)
            jmp DrawTitle
.g          jmp DrawGame
.o          sta WSYNC
            lda #0
            sta VBLANK
            jmp DrawOver
.lv         sta WSYNC
            lda #0
            sta VBLANK
            jmp DrawDigitScreen
.sc         sta WSYNC
            lda #0
            sta VBLANK
            jmp DrawDigitScreen

DrawTitle SUBROUTINE
            ldx SubState
            cpx #TITLE_KEITH
            beq .tK
            cpx #TITLE_ADLER
            beq .tA
            cpx #TITLE_PRESENTS
            beq .tP
            cpx #TITLE_CYLOID
            beq .tC
            jmp RenderBlack
.tK         jmp RenderKeith
.tA         jmp RenderAdler
.tP         jmp RenderPresents
.tC         jmp RenderCyloid

;===============================================================================
; GAME KERNEL
;===============================================================================
DrawGame SUBROUTINE
            ; Position sprites DURING VBLANK (before visible area)
            lda TankX
            sec
            sta WSYNC
.d0         sbc #15
            bcs .d0
            eor #7
            asl
            asl
            asl
            asl
            sta HMP0
            sta RESP0
            lda TgtX
            sec
            sta WSYNC
.d1         sbc #15
            bcs .d1
            eor #7
            asl
            asl
            asl
            asl
            sta HMP1
            sta RESP1
            lda MissileX
            sec
            sta WSYNC
.dm         sbc #15
            bcs .dm
            eor #7
            asl
            asl
            asl
            asl
            sta HMM0
            sta RESM0
            sta WSYNC
            sta HMOVE

            ; Colors (VBLANK already turned off in lives area above)
            lda HitFlash
            beq .nc
            lda FrameCount
            asl
            asl
            eor HitFlash
            and #$FE
            sta COLUP0
            lda FrameCount
            eor HitFlash
            and #$0E
            ora #$00            ; black background during death flash
            sta COLUBK
            jmp .colorDone
.nc         lda #$9E
            sta COLUP0
            lda #$00            ; black field background
            sta COLUBK
.colorDone
            ; Target/boss color
            lda TgtLive
            cmp #50             ; boss?
            bcs .bossColor
            cmp #2              ; dying target?
            bcc .normTgt
            ; Dying target: flash white
            lda FrameCount
            and #2
            beq .tgtWhite
            lda TgtColor
            jmp .setTgt
.bossColor
            ; Boss: bright yellow/white, distinct from targets
            lda #$1E            ; bright yellow
            jmp .setTgt
.tgtWhite   lda #$0E
            jmp .setTgt
.normTgt    lda TgtColor
            clc
            adc FrameCount
            and #$06
            ora TgtColor
.setTgt     sta COLUP1

            lda #$0E
            sta COLUPF
            lda #%00000001
            sta CTRLPF
            lda #%00100000
            sta NUSIZ0
            lda #0
            sta GRP0
            sta GRP1
            sta ENAM0
            sta ENABL
            sta PF0
            sta PF1
            sta PF2

            ldx #0

            ; Top border: 8 lines with life indicators
            ; #7: Flash red when boss just spawned (BossActive=1, BossX < 10)
            lda BossActive
            cmp #1
            bne .normalBorder
            lda BossX
            cmp #15
            bcs .normalBorder
            lda #$42            ; red flash!
            sta COLUBK
            jmp .borderColor
.normalBorder
            lda #$00
.borderColor
            sta COLUBK
            sta PF0
            sta PF2
            sta GRP0
            sta GRP1
            ; Lives as PF1 centered blocks
            lda Lives
            cmp #3
            bcc .lp2
            lda #%00101010      ; 3 pips centered
            jmp .lpSet
.lp2        cmp #2
            bcc .lp1
            lda #%00101000      ; 2 pips
            jmp .lpSet
.lp1        cmp #1
            bcc .lp0
            lda #%00100000      ; 1 pip
            jmp .lpSet
.lp0        lda #0
.lpSet      sta PF1
            lda #$9E            ; cyan
            sta COLUPF

            ; Turn on display
            sta WSYNC
            lda #0
            sta VBLANK          ; A must be 0 to turn off blanking

            ldx #0
.topBorder  sta WSYNC
            inx
            cpx #6              ; show pips for 6 lines
            bne .topBorder
            ; Clear for last 2 lines
            lda #0
            sta PF1
            sta COLUPF
            sta WSYNC
            inx
            sta WSYNC
            inx
            ; X=8, total border = 8 lines

            ; Field area: 176 lines
            lda #$00            ; black background
            sta COLUBK
            lda WallColor
            ora #$08
            sta COLUPF

            ; Boss ball uses software collision (no ENABL)

            lda TankY
            clc
            adc #TANK_H
            sta TempVar

            ; 2-line kernel — cycle-tight
.fLoop
            ; LINE 1: obstacles + tank
            ; Obstacle check: if (X & $1F) >= $18, show obstacle
            txa                 ; 2
            and #$1F            ; 2
            cmp #$18            ; 2
            bcc .obsOff         ; 2/3

            ; Obstacle ON — get band index
            txa                 ; 2
            lsr                 ; 2
            lsr                 ; 2
            lsr                 ; 2
            lsr                 ; 2
            lsr                 ; 2
            and #3              ; 2
            tay                 ; 2
            lda ObsPF1,y        ; 4
            sta PF1             ; 3
            lda ObsPF2,y        ; 4
            sta PF2             ; 3 = 35 cycles
            jmp .tankChk        ; 3 = 38

.obsOff     lda #0              ; 2
            sta PF1             ; 3
            sta PF2             ; 3

.tankChk
            ; Tank sprite — simplified: just index and store
            cpx TankY           ; 3
            bcc .noTank         ; 2/3
            cpx TempVar         ; 3
            bcs .noTank         ; 2/3
            txa                 ; 2
            sec                 ; 2
            sbc TankY           ; 3
            tay                 ; 2
            lda TankGfxBuf,y    ; 4
            sta GRP0            ; 3
            inx                 ; 2
            sta WSYNC           ; 3
            jmp .line2          ; 3

.noTank     lda #0              ; 2
            sta GRP0            ; 3
            inx                 ; 2
            sta WSYNC           ; 3

            ; LINE 2: target + missile
.line2
            lda TgtLive         ; 3
            beq .noTgt          ; 2/3
            txa                 ; 2
            sec                 ; 2
            sbc TgtY            ; 3
            cmp #6              ; 2
            bcs .noTgt          ; 2/3
            tay                 ; 2
            lda TgtLive         ; 3
            cmp #2              ; 2
            bcs .tgtExp         ; 2/3
            lda TargetGfx,y     ; 4  normal sprite
            jmp .storeTgt       ; 3
.tgtExp     tya                 ; 2  explosion: random from Y + frame
            eor FrameCount      ; 3
.storeTgt   sta GRP1            ; 3
            jmp .tgtDone        ; 3

.noTgt      lda #0              ; 2
            sta GRP1            ; 3

.tgtDone
            ; Missile
            lda MissileOn       ; 3
            beq .noMsl          ; 2/3
            txa                 ; 2
            sec                 ; 2
            sbc MissileY        ; 3
            bcc .noMsl          ; 2/3
            cmp #6              ; #10: missile trail (6 scanlines tall)
            bcs .noMsl
            lda #2              ; 2
            sta ENAM0           ; 3
            jmp .mslDone        ; 3

.noMsl      lda #0              ; 2
            sta ENAM0           ; 3

.mslDone
            inx                 ; 2
            cpx #184            ; 2
            beq .fEnd           ; 2/3
            sta WSYNC           ; 3
            jmp .fLoop          ; 3
.fEnd
            ; Bottom border: 8 black lines (replaces wall + blank)
            lda #0
            sta PF0
            sta PF1
            sta PF2
            sta GRP0
            sta GRP1
            sta ENAM0
            sta COLUBK
            sta COLUPF
.bot        sta WSYNC
            inx
            cpx #192
            bne .bot
            jmp DoOverscan

;===============================================================================
; DIGIT SCREEN (shared by level-up and post-game-over score)
;===============================================================================
DrawDigitScreen SUBROUTINE
            lda #$00
            sta COLUBK
            sta GRP0
            sta GRP1
            sta ENAM0
            sta ENABL
            sta PF0
            sta PF1
            sta PF2

            lda TensOff
            cmp #$FF
            bne .twoDigits
            jmp .single
.twoDigits

            ; TWO DIGITS: P0 at X=70, P1 at X=90 (centered)
            lda #70
            sec
            sta WSYNC
.d0         sbc #15
            bcs .d0
            eor #7
            asl
            asl
            asl
            asl
            sta HMP0
            sta RESP0
            lda #90
            sec
            sta WSYNC
.d1         sbc #15
            bcs .d1
            eor #7
            asl
            asl
            asl
            asl
            sta HMP1
            sta RESP1
            sta WSYNC
            sta HMOVE

            lda FrameCount
            lsr
            and #$0E
            ora #$C0
            sta COLUP0
            sta COLUP1

            ; Top: 72 lines
            ldx #72
.top2       sta WSYNC
            dex
            bne .top2

            ; Score digits: 16 lines
            ldy #0
.dr2        tya
            clc
            adc TensOff
            tax
            lda DigitSprites,x
            sta GRP0
            tya
            clc
            adc OnesOff
            tax
            lda DigitSprites,x
            sta GRP1
            sta WSYNC
            sta WSYNC
            iny
            cpy #8
            bne .dr2

            lda #0
            sta GRP0
            sta GRP1

            ; Bottom: 192 - 72 - 16 = 104 lines
            ldx #104
.bot2       sta WSYNC
            dex
            bne .bot2
            jmp DoOverscan

.single
            ; ONE DIGIT: P0 at X=78 (centered)
            lda #78
            sec
            sta WSYNC
.d0s        sbc #15
            bcs .d0s
            eor #7
            asl
            asl
            asl
            asl
            sta HMP0
            sta RESP0
            sta WSYNC
            sta HMOVE

            lda FrameCount
            lsr
            and #$0E
            ora #$C0
            sta COLUP0

            ; Top: 74 lines
            ldx #74
.top1       sta WSYNC
            dex
            bne .top1

            ; Score digit: 16 lines
            ldy #0
.dr1        tya
            clc
            adc OnesOff
            tax
            lda DigitSprites,x
            sta GRP0
            sta WSYNC
            sta WSYNC
            iny
            cpy #8
            bne .dr1

            lda #0
            sta GRP0

            ; Bottom: 192 - 74 - 16 = 102 lines
            ldx #102
.bot1       sta WSYNC
            dex
            bne .bot1
            jmp DoOverscan

;===============================================================================
; GAME OVER
;===============================================================================
DrawOver SUBROUTINE
            sta WSYNC
            lda #0
            sta VBLANK
            lda #$00
            sta COLUBK
            sta GRP0
            sta GRP1
            sta ENAM0
            sta ENABL
            sta PF0
            sta PF1
            sta PF2
            sta COLUP0
            sta COLUP1
            lda #%00000001      ; reflect mode for asymmetric
            sta CTRLPF

            ; Top: 46 lines
            ldx #46
.top        sta WSYNC
            dex
            bne .top

            ; GAME text: 8 rows × 5 scanlines + 8 gap = 48 lines
            ldy #0
.gameRow
            lda FrameCount
            lsr
            and #$0E
            ora #$20
            sta COLUPF
            ldx #5
.gameSc     sta WSYNC
            lda GameLPF0,y
            sta PF0
            lda GameLPF1,y
            sta PF1
            lda GameLPF2,y
            sta PF2
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            lda GameRPF2,y
            sta PF2
            lda GameRPF1,y
            sta PF1
            lda GameRPF0,y
            sta PF0
            dex
            bne .gameSc
            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            iny
            cpy #8
            bne .gameRow

            ; Gap: 16 lines
            ldx #16
.gap        sta WSYNC
            dex
            bne .gap

            ; OVER text: 8 rows × 5 scanlines + 8 gap = 48 lines
            ldy #0
.overRow
            lda FrameCount
            lsr
            and #$0E
            ora #$20
            sta COLUPF
            ldx #5
.overSc     sta WSYNC
            lda OverLPF0,y
            sta PF0
            lda OverLPF1,y
            sta PF1
            lda OverLPF2,y
            sta PF2
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            lda OverRPF2,y
            sta PF2
            lda OverRPF1,y
            sta PF1
            lda OverRPF0,y
            sta PF0
            dex
            bne .overSc
            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            iny
            cpy #8
            bne .overRow

            ; Bottom: 192 - 1 - 46 - 48 - 16 - 48 = 33 lines
            ldx #33
.bot        sta WSYNC
            dex
            bne .bot
            jmp DoOverscan

;===============================================================================
; OVERSCAN
;===============================================================================
DoOverscan
            ; === OVERSCAN: 30 lines ===
            lda #2
            sta VBLANK          ; turn on VBLANK
            lda #0
            sta GRP0
            sta GRP1
            sta ENAM0
            sta ENABL
            sta PF0
            sta PF1
            sta PF2
            ldx #30
.ov         sta WSYNC
            dex
            bne .ov
            jmp MainLoop

;===============================================================================
; TITLE RENDERERS
;===============================================================================
DrawText1 SUBROUTINE
            ldy #67             ; 67 + 1 VBLANK-off line = 68 total top
.t          sta WSYNC
            dey
            bne .t
            ldy #0
.row        lda PFData0,y
            sta TempVar
            ldx #6
.sc         sta WSYNC
            lda TempVar
            sta PF0
            lda PFData1,y
            sta PF1
            lda PFData2,y
            sta PF2
            dex
            bne .sc
            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            iny
            cpy #8
            bne .row
            ldy #68
.b          sta WSYNC
            dey
            bne .b
            rts

RenderKeith SUBROUTINE
            sta WSYNC
            lda #0
            sta VBLANK
            lda #$00
            sta COLUBK
            lda FrameCount
            lsr
            and #$0E
            ora #$72
            sta COLUPF
            lda #%00000001
            sta CTRLPF
            ldx #0
.cp         lda KeithR0,x
            sta PFData0,x
            lda KeithR1,x
            sta PFData1,x
            lda KeithR2,x
            sta PFData2,x
            inx
            cpx #8
            bne .cp
            jsr DrawText1
            jmp DoOverscan

RenderAdler SUBROUTINE
            sta WSYNC
            lda #0
            sta VBLANK
            lda #$00
            sta COLUBK
            lda FrameCount
            lsr
            and #$0E
            ora #$72
            sta COLUPF
            lda #%00000001
            sta CTRLPF
            ldx #0
.cp         lda AdlerR0,x
            sta PFData0,x
            lda AdlerR1,x
            sta PFData1,x
            lda AdlerR2,x
            sta PFData2,x
            inx
            cpx #8
            bne .cp
            jsr DrawText1
            jmp DoOverscan

RenderPresents SUBROUTINE
            sta WSYNC
            lda #0
            sta VBLANK
            lda #$00
            sta COLUBK
            lda #%00000001      ; REFLECT mode for asymmetric
            sta CTRLPF
            lda #0
            sta PF0
            sta PF1
            sta PF2

            ldy #64             ; 64 top lines
.top        sta WSYNC
            dey
            bne .top

            ldy #0
.row        lda #$1C            ; gold color
            sta COLUPF
            ldx #7
.scan       sta WSYNC
            lda PresLPF0,y
            sta PF0
            lda PresLPF1,y
            sta PF1
            lda PresLPF2,y
            sta PF2
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            lda PresRPF2,y
            sta PF2
            lda PresRPF1,y
            sta PF1
            lda PresRPF0,y
            sta PF0
            dex
            bne .scan
            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            iny
            cpy #8
            bne .row

            ldy #64             ; 64 bottom
.bot        sta WSYNC
            dey
            bne .bot
            jmp DoOverscan

RenderCyloid SUBROUTINE
            ; Calculate ship position
            lda #180
            sec
            sbc StateTimer      ; 0 to 180
            cmp #156
            bcc .shipVisible
            ; Ship off-screen
            lda #0
            sta TgtLive
            ; Still need WSYNC lines for timing
            sta WSYNC
            sta WSYNC
            sta WSYNC
            jmp .afterPos
.shipVisible
            sta TgtLive
            ; Position tank during VBLANK
            sec
            sta WSYNC
.posT       sbc #15
            bcs .posT
            eor #7
            asl
            asl
            asl
            asl
            sta HMP0
            sta RESP0
            sta WSYNC
            sta HMOVE
.afterPos

            ; NOW turn on display
            lda #$9E
            sta COLUP0
            lda #0
            sta COLUBK
            sta PF0
            sta PF1
            sta PF2
            sta WSYNC
            sta VBLANK          ; display on

            ; Engine rumble
            lda #6
            sta AUDC1
            lda #3
            sta AUDV1
            lda FrameCount
            and #1
            clc
            adc #30
            sta AUDF1

            lda #%00000001
            sta CTRLPF

            ; Load tank-right sprite
            ldx #0
.loadTank   lda TankRightGfx,x
            sta TankGfxBuf,x
            inx
            cpx #8
            bne .loadTank

            ; Clear P0 so tank doesn't show during text
            lda #0
            sta GRP0

            ; Top blank: 59 lines
            ldy #59
.top        sta WSYNC
            dey
            bne .top

            ; Asymmetric PF kernel: 8 rows x 7 scanlines = 56 lines
            ; Tank flies at scanline ~48 (row 6-7 area, Y=48 relative to text start)
            ldy #0
.row
            lda FrameCount
            lsr
            and #$0E
            ora #$C2
            sta COLUPF

            ldx #7
.scanLine
            sta WSYNC
            ; Left PF
            lda CycLPF0,y
            sta PF0
            lda CycLPF1,y
            sta PF1
            lda CycLPF2,y
            sta PF2
            ; NOP sled for right half
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            nop
            ; Right PF
            lda CycRPF2,y
            sta PF2
            lda CycRPF1,y
            sta PF1
            lda CycRPF0,y
            sta PF0

            dex
            bne .scanLine

            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2

            iny
            cpy #8
            bne .row

            ; Gap after text: 8 lines
            ldy #8
.gap        sta WSYNC
            dey
            bne .gap

            ; Tank fly area: 16 lines
            ldx #0
.tankArea   sta WSYNC
            lda TgtLive         ; ship visible?
            beq .noShip
            cpx #4
            bcc .noShip
            cpx #12
            bcs .noShip
            txa
            sec
            sbc #4
            tay
            lda TankGfxBuf,y
            sta GRP0
            jmp .shipDone
.noShip     lda #0
            sta GRP0
.shipDone   inx
            cpx #16
            bne .tankArea

            ; Clear sprite
            lda #0
            sta GRP0

            ; Bottom blank: remaining lines (60+56+8+8+16 = 148, need 192-148 = 44)
            ldy #44
.bot        sta WSYNC
            dey
            bne .bot

            ; Silence engine when ship off-screen
            lda TgtLive
            bne .noSilence
            lda #0
            sta AUDV1
.noSilence

            jmp DoOverscan

            jmp DoOverscan

RenderBlack SUBROUTINE
            sta WSYNC
            lda #0
            sta VBLANK
            sta COLUBK
            sta COLUPF
            sta PF0
            sta PF1
            sta PF2
            ldx #191            ; 191 + 1 VBLANK-off = 192
.bk         sta WSYNC
            dex
            bne .bk
            jmp DoOverscan

;===============================================================================
; DATA
;===============================================================================

; Sprite tables ordered by TankDir: 0=up, 1=right, 2=down, 3=left
TankUpGfx
            .byte #%00011000,#%00011000,#%01111110,#%01111110
            .byte #%11111111,#%11111111,#%01100110,#%01100110
TankRightGfx
            .byte #%00111100,#%01111110,#%01111111,#%11111111
            .byte #%11111111,#%01111111,#%01111110,#%00111100
TankDownGfx
            .byte #%01100110,#%01100110,#%11111111,#%11111111
            .byte #%01111110,#%01111110,#%00011000,#%00011000
TankLeftGfx
            .byte #%00111100,#%01111110,#%11111110,#%11111111
            .byte #%11111111,#%11111110,#%01111110,#%00111100
TargetGfx
            .byte #%00011000,#%00111100,#%01111110
            .byte #%01111110,#%00111100,#%00011000

LvlField    .byte $D6,$B4,$96,$F6,$C6,$06,$76,$46
LvlWall     .byte $D2,$B0,$94,$F2,$C2,$04,$72,$44
LvlTgt      .byte $36,$2A,$1C,$44,$C8,$9A,$36,$1C
; All levels have movement now
LvlDirX     .byte $01,$FF,$01,$FF,$01,$FF,$01,$FF
LvlDirY     .byte $00,$01,$FF,$01,$FF,$01,$FF,$01

; Obstacle density masks per level (more bits = more obstacles)
; Level 0: very sparse, Level 7: very dense
LvlObsMask  .byte %00010000    ; 0: minimal
            .byte %00100100    ; 1: light
            .byte %01001010    ; 2: moderate
            .byte %01011010    ; 3: medium
            .byte %01101110    ; 4: heavy
            .byte %01111110    ; 5: dense
            .byte %01111110    ; 6: dense
            .byte %01111110    ; 7: max

; Bug 3: safe Y positions for targets (avoid all obstacle bands)
SafeYTbl    .byte 40,70,105,135,165

; #1: Tank multicolor table (indexed by sprite row 0-7)
; Rows 0-1: treads (brown), 2-5: body (cyan), 6-7: turret (white)
TankColors  .byte $F2,$F2,$9E,$9E,$9E,$9E,$0E,$0E

MelodyNotes .byte 8,9,11,12,15,17,20,24
MelodyVols  .byte 12,11,10,9,8,7,5,3

; Game Over melody — subtle, quiet, somber
GONotes     .byte 15,17,20,22,25,27,30,31
GOVols      .byte 6,5,5,4,4,3,3,2

; Victory jingle - gentle ascending chime (6 notes)
VictoryNotes .byte 20,15,12,10,8,6
VictoryVols  .byte 6,7,7,8,8,6

KeithR0     .byte $50,$50,$30,$10,$30,$50,$50,$50
KeithR1     .byte $EE,$84,$84,$E4,$84,$84,$EE,$EE
KeithR2     .byte $57,$52,$52,$72,$52,$52,$52,$52
AdlerR0     .byte $20,$50,$50,$70,$50,$50,$50,$50
AdlerR1     .byte $C8,$A8,$A8,$A8,$A8,$A8,$CE,$CE
AdlerR2     .byte $77,$51,$51,$77,$31,$51,$57,$57
; PRESENTS - asymmetric playfield
PresLPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
PresLPF1    .byte $77,$55,$55,$77,$46,$45,$45,$45
PresLPF2    .byte $EE,$22,$22,$EE,$82,$82,$EE,$EE
PresRPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
PresRPF1    .byte $EE,$24,$24,$E4,$84,$84,$E4,$E4
PresRPF2    .byte $75,$47,$47,$75,$45,$45,$75,$75
; GAME - asymmetric playfield
GameLPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
GameLPF1    .byte $00,$00,$00,$00,$00,$00,$00,$00
GameLPF2    .byte $4E,$A2,$A2,$EA,$AA,$AA,$AE,$AE
GameRPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
GameRPF1    .byte $00,$00,$00,$00,$00,$00,$00,$00
GameRPF2    .byte $57,$74,$74,$57,$54,$54,$57,$57

; OVER - asymmetric playfield
OverLPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
OverLPF1    .byte $00,$00,$00,$00,$00,$00,$00,$00
OverLPF2    .byte $AE,$AA,$AA,$AA,$AA,$4A,$4E,$4E
OverRPF0    .byte $00,$00,$00,$00,$00,$00,$00,$00
OverRPF1    .byte $00,$00,$00,$00,$00,$00,$00,$00
OverRPF2    .byte $77,$45,$45,$77,$46,$45,$75,$75

; CYLOID - asymmetric playfield (mid-scanline PF update trick)
CycLPF0     .byte $00,$00,$00,$00,$00,$00,$00,$00
CycLPF1     .byte $07,$04,$04,$04,$04,$04,$07,$07
CycLPF2     .byte $2A,$2A,$24,$24,$24,$24,$E4,$E4
CycRPF0     .byte $00,$00,$00,$00,$00,$00,$00,$00
CycRPF1     .byte $06,$0A,$0A,$0A,$0A,$0A,$06,$06
CycRPF2     .byte $77,$52,$52,$52,$52,$52,$77,$77

DigitSprites
            .byte $38,$44,$44,$44,$44,$44,$38,$38  ; 0
            .byte $10,$30,$10,$10,$10,$10,$38,$38  ; 1
            .byte $38,$44,$04,$18,$20,$40,$7C,$7C  ; 2
            .byte $38,$44,$04,$18,$04,$44,$38,$38  ; 3
            .byte $08,$18,$28,$48,$7C,$08,$08,$08  ; 4
            .byte $7C,$40,$78,$04,$04,$44,$38,$38  ; 5
            .byte $38,$40,$40,$78,$44,$44,$38,$38  ; 6
            .byte $7C,$04,$08,$10,$20,$20,$20,$20  ; 7
            .byte $38,$44,$44,$38,$44,$44,$38,$38  ; 8
            .byte $38,$44,$44,$3C,$04,$08,$30,$30  ; 9

            ORG $FFFA
            .word Reset
            .word Reset
            .word Reset

            END
