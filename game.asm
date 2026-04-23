; game.asm - Cyloid Tank Game - Atari 2600 (4KB)
; Build: dasm game.asm -f3 -ogame.bin

            processor 6502
            include "vcs.h"
            include "macro.h"

;===============================================================================
; Constants
;===============================================================================

MODE_TITLE     = 0
MODE_PLAY      = 1
MODE_OVER      = 2
MODE_LVLUP     = 3
MODE_SCORE     = 4          ; score display after game over

TITLE_KEITH    = 0
TITLE_ADLER    = 1
TITLE_PRESENTS = 2
TITLE_CYLOID   = 3
TITLE_BLACK    = 4
NUM_TITLE      = 5

TANK_H         = 8
MAX_TGTS       = 5          ; max enemies per level

;===============================================================================
; Variables
;===============================================================================

            SEG.U Variables
            ORG $80

GameMode    ds 1
SubState    ds 1
StateTimer  ds 1
FrameCount  ds 1
TempVar     ds 1

PFData0     ds 8
PFData1     ds 8
PFData2     ds 8

TankX       ds 1
TankY       ds 1
TankDir     ds 1

MissileX    ds 1
MissileY    ds 1
MissileDir  ds 1
MissileOn   ds 1

; Current flicker-selected target for kernel
TgtX        ds 1
TgtY        ds 1
TgtLive     ds 1

; Target arrays (5 targets max)
TgtAX       ds MAX_TGTS
TgtAY       ds MAX_TGTS
TgtALive    ds MAX_TGTS     ; 0=dead, 1=alive, 2+=dying (death timer)
TgtADirX    ds MAX_TGTS
TgtADirY    ds MAX_TGTS
NumTgts     ds 1            ; how many targets this level (1-5)
FlickerIdx  ds 1

Score       ds 1
ButtonPrev  ds 1
SndVol      ds 1
Lives       ds 1
HitFlash    ds 1
Level       ds 1
KillCount   ds 1
FieldColor  ds 1
WallColor   ds 1
TgtColor    ds 1

TankGfxBuf  ds 8
ObsPF1      ds 4
ObsPF2      ds 4
Moving      ds 1
MelodyIdx   ds 1
MelodyTimer ds 1
TensOff     ds 1
OnesOff     ds 1
SndType     ds 1

; Boss (player 2 flyby)
BossX       ds 1            ; horizontal position
BossY       ds 1            ; vertical position (scanline)
BossActive  ds 1            ; 0=inactive, 1=flying
BossTimer   ds 1            ; countdown to next appearance
BossBallY   ds 1            ; boss bullet Y position
BossBallOn  ds 1            ; boss bullet active

;===============================================================================
; Code
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
            sta BossBallOn
            lda #240            ; boss appears after ~4 seconds
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
            ; === EVERY FRAME: joystick + fire (must be responsive) ===
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

            ; === EVEN FRAME: missile + hit detection ===
.evenFrame
            lda MissileOn
            bne .mGo
            jmp .frameDone

.mGo        ; Check if missile hit background (from last frame's kernel)
            lda CXM0FB          ; bit 7 = M0 vs PF
            bpl .noWallHit
            ; Missile hit wall — kill it with sad sound
            lda #0
            sta MissileOn
            lda #3              ; low buzz
            sta AUDC0
            lda #8
            sta SndVol
            sta AUDV0
            lda #20             ; low pitch = sad
            sta AUDF0
            lda #1
            sta SndType
            jmp .frameDone

.noWallHit
            ldx MissileDir
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
            jmp .frameDone

.mHit       ; Check 2 targets per frame for reliable detection
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

.try2nd     ; Check next target
            inx
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

.hitTarget  ; HIT!
            lda #15
            sta TgtALive,x
            lda #0
            sta MissileOn
            inc Score
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

            ; Check boss hit (quick — only if boss active)
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
            ; Boss hit! 5 points
            lda #0
            sta BossActive
            sta BossBallOn
            sta MissileOn
            lda Score
            clc
            adc #5
            cmp #41
            bcc .bscOk
            lda #40
.bscOk      sta Score
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

            ; === ODD FRAME: death timers + move + flicker + collision ===
.oddFrame
            ; Death timers + alive check
            ldx #0
            ldy #0
.deathLoop  cpx NumTgts
            bcs .deathDone
            lda TgtALive,x
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

            ; Move targets every 4th frame
            lda FrameCount
            and #7              ; every 8th frame now (was 4th)
            bne .skipMv
            jsr MoveTargets
.skipMv

            ; Flicker select (inline)
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
.fFound     sta TgtLive
            lda TgtAX,x
            sta TgtX
            lda TgtAY,x
            sta TgtY
.fDone

            ; === BOSS LOGIC (only every 4th frame to save cycles) ===
            lda FrameCount
            and #3
            beq .doBossLogic
            jmp .bossSkipLogic
.doBossLogic

            lda BossActive
            bne .bossMove
            dec BossTimer
            beq .spawnBoss
            jmp .bossEnd
.spawnBoss
            lda #1
            sta BossActive
            lda #0
            sta BossX
            lda FrameCount
            eor Score
            and #$7F
            clc
            adc #30
            cmp #150
            bcc .byOk
            lda #80
.byOk       sta BossY
            lda #0
            sta BossBallOn
            jmp .bossEnd

.bossMove
            ; Move boss right (4px since we run every 4th frame)
            lda BossX
            clc
            adc #4
            sta BossX
            cmp #160
            bcc .bossOnScreen
            lda #0
            sta BossActive
            sta BossBallOn
            lda FrameCount
            ora #$78
            sta BossTimer
            jmp .bossEnd

.bossOnScreen
            lda BossBallOn
            bne .moveBossBall
            lda BossX
            sec
            sbc TankX
            bcs .bxp
            eor #$FF
            adc #1
.bxp        cmp #20
            bcs .bossEnd
            lda #1
            sta BossBallOn
            lda BossY
            clc
            adc #8
            sta BossBallY
            lda #14
            sta AUDC1
            lda #8
            sta AUDV1
            lda #12
            sta AUDF1

.moveBossBall
            ; Move ball toward player Y
            lda BossBallY
            cmp TankY
            bcs .ballUp
            ; Ball below player — move down
            clc
            adc #4
            sta BossBallY
            cmp #185
            bcc .bossEnd
            lda #0
            sta BossBallOn
            jmp .bossEnd
.ballUp     ; Ball above player — move up
            sec
            sbc #4
            sta BossBallY
            cmp #8
            bcs .bossEnd
            lda #0
            sta BossBallOn

.bossEnd
.bossSkipLogic
            ; Show boss on P1 every 3rd frame (use simple counter)
            lda BossActive
            beq .noBossFrame
            lda FrameCount
            and #$03            ; every 4th frame = boss on P1
            bne .noBossFrame
            lda BossX
            sta TgtX
            lda BossY
            sta TgtY
            lda #1
            sta TgtLive
.noBossFrame

            ; Collision
            lda HitFlash
            bne .skipC
            lda CXP0FB
            bmi .doDeath        ; P0 vs PF (bit 7)
            ; Check P0 vs Ball (boss bullet) — bit 6 of CXP0FB
            lda CXP0FB
            and #%01000000
            bne .doDeath
            lda CXPPMM
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
.skipC      sta CXCLR

            ; === EVERY FRAME (after split): flash + gfx + sound ===
.frameDone
            lda HitFlash
            beq .noFl
            dec HitFlash
            bne .flashCont
            lda #78
            sta TankX
            lda #170
            sta TankY
            lda #0
            sta AUDV1
            lda Lives
            bne .noFl
            lda #0
            sta SndVol
            sta AUDV0
            lda #MODE_OVER
            sta GameMode
            lda #180
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
            ; Tank gfx
            lda HitFlash
            bne .doExp
            jsr BufTankGfx
            jmp .gfxDone
.doExp      lda FrameCount
            eor HitFlash
            ldx #7
.expLp      eor TankGfxBuf,x
            sta TankGfxBuf,x
            dex
            bpl .expLp
.gfxDone

            ; Sound decay
            lda SndType
            beq .nsd
            lda FrameCount
            and #1
            bne .nsd
            lda SndVol
            beq .sndOff
            sec
            sbc #1
            sta SndVol
            sta AUDV0
            jmp .nsd
.sndOff     lda #0
            sta SndVol
            sta AUDV0
            sta SndType
.nsd
            ; Movement sound
            lda HitFlash
            bne .moveDone
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

            lda Score
            cmp #40
            bcc .noWin
            lda #0
            sta SndVol
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
.noWin      jmp WaitDraw

MoveTargets SUBROUTINE
            ldx #0
.loop       cpx NumTgts
            bcs .done
            lda TgtALive,x
            cmp #1
            bne .next           ; skip dead and dying
            ; Move X
            lda TgtADirX,x
            beq .my
            cmp #1
            bne .ml
            inc TgtAX,x
            lda TgtAX,x
            cmp #135
            bcc .my
            lda #$FF
            sta TgtADirX,x
            jmp .my
.ml         dec TgtAX,x
            lda TgtAX,x
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
            lda TgtAY,x
            cmp #155
            bcc .next
            lda #$FF
            sta TgtADirY,x
            jmp .next
.mu         dec TgtAY,x
            lda TgtAY,x
            cmp #15
            bcs .next
            lda #1
            sta TgtADirY,x
.next       inx
            cpx NumTgts         ; Opt 6: use bcc instead of jmp
            bcc .loop
.done       rts

BufTankGfx SUBROUTINE
            ; Opt 5: compute table base offset, single copy loop
            lda TankDir
            asl
            asl
            asl                 ; dir * 8
            tay                 ; Y = offset into sprite tables
            ldx #0
.copy       lda TankUpGfx,y     ; all 4 tables are contiguous
            sta TankGfxBuf,x
            iny
            inx
            cpx #TANK_H
            bne .copy
            rts

;===============================================================================
; LEVEL UP / SCORE / GAME OVER LOGIC
;===============================================================================
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
            cpx #12             ; 12 notes
            bcs .jingleDone
            lda VictoryNotes,x
            sta AUDF1
            lda #4              ; pure tone
            sta AUDC1
            lda VictoryVols,x
            sta AUDV1
            lda #8              ; 8 frames per note (fast arpeggio)
            sta MelodyTimer
            inc MelodyIdx
            jmp .skip
.jingleDone lda #0
            sta AUDV1
.skip       jmp WaitDraw

ScoreLogic SUBROUTINE
            dec StateTimer
            bne .wait
            lda #0
            sta AUDV0
            sta AUDV1
            lda #MODE_TITLE
            sta GameMode
            lda #TITLE_KEITH
            sta SubState
            lda #180
            sta StateTimer
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
            ; Score screen uses game over melody (already defined)
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
            ; Go to score screen (not directly to title)
            lda #0
            sta SndVol
            sta AUDV0
            sta AUDV1
            lda #MODE_SCORE
            sta GameMode
            lda #150
            sta StateTimer
            jmp WaitDraw
.melody
            dec MelodyTimer
            bne .w
            ldx MelodyIdx
            cpx #8
            bcs .melDone
            lda MelodyNotes,x
            sta AUDF1
            lda #12
            sta AUDC1
            lda MelodyVols,x
            sta AUDV1
            lda #25
            sta MelodyTimer
            inc MelodyIdx
            jmp .w
.melDone    lda #0
            sta AUDV1
            lda #255            ; Bug 8: prevent wrap-around re-triggering
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
            ; Position boss ball (Ball object)
            lda BossBallOn
            beq .skipBallPos
            lda BossX           ; ball X = boss X
            sec
            sta WSYNC
.dbl        sbc #15
            bcs .dbl
            eor #7
            asl
            asl
            asl
            asl
            sta HMBL
            sta RESBL
.skipBallPos
            sta WSYNC
            sta HMOVE

            ; Turn on display — set black first, then WSYNC+VBLANK
            lda #0
            sta COLUBK
            sta COLUPF
            sta PF0
            sta PF1
            sta PF2
            sta GRP0
            sta GRP1
            sta ENAM0
            sta WSYNC           ; this line is the first visible line (black)
            sta VBLANK          ; display fully on for next line

            ; Colors
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
            ; Target color: dying targets flash white
            lda TgtLive
            cmp #2
            bcc .normTgt
            lda FrameCount
            and #2
            beq .tgtWhite
            lda TgtColor
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

            ; Top border: 8 black lines
            lda #$00
            sta COLUBK
            sta COLUPF
            sta PF0
            sta PF1
            sta PF2
.topBorder  sta WSYNC
            inx
            cpx #8              ; 8 black border lines
            bne .topBorder

            ; Field area: 176 lines
            lda #$00            ; black background
            sta COLUBK
            lda WallColor
            ora #$08
            sta COLUPF

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
            sta PF2             ; 3 = 12 cycles (fast path)

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
            sta GRP0            ; 3 = 24 cycles
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
            cmp #4              ; 2
            bcs .noMsl          ; 2/3
            lda #2              ; 2
            sta ENAM0           ; 3
            jmp .mslDone        ; 3

.noMsl      lda #0              ; 2
            sta ENAM0           ; 3

.mslDone
            ; Boss ball (Ball object) — 2 lines tall
            lda BossBallOn      ; 3
            beq .noBall         ; 2/3
            txa                 ; 2
            sec                 ; 2
            sbc BossBallY       ; 3
            cmp #2              ; 2
            bcs .noBall         ; 2/3
            lda #2              ; 2
            sta ENABL           ; 3
            jmp .ballDone       ; 3
.noBall     lda #0              ; 2
            sta ENABL           ; 3
.ballDone
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
            beq .single

            ; TWO DIGITS: P0 at X=65, P1 at X=85
            lda #65
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
            lda #85
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

            ldx #84
.top2       sta WSYNC
            dex
            bne .top2

            ldy #0
.dr2        ; Use Y as row offset, add to base offsets
            tya
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
            ldx #88
.bot2       sta WSYNC
            dex
            bne .bot2
            jmp DoOverscan

.single
            ; ONE DIGIT: P0 centered at X=76
            lda #76
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

            ldx #86
.top1       sta WSYNC
            dex
            bne .top1

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
            ldx #88
.bot1       sta WSYNC
            dex
            bne .bot1
            jmp DoOverscan

;===============================================================================
; GAME OVER
;===============================================================================
DrawOver SUBROUTINE
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
            lda FrameCount
            lsr
            and #$0E
            ora #$20
            sta COLUPF
            lda #%00000001
            sta CTRLPF

            ldx #48
.top        sta WSYNC
            dex
            bne .top

            ldy #0
.gameRow    lda GameR0,y
            sta TempVar
            ldx #5
.gameSc     sta WSYNC
            lda TempVar
            sta PF0
            lda GameR1,y
            sta PF1
            lda GameR2,y
            sta PF2
            dex
            bne .gameSc
            iny
            cpy #8
            bne .gameRow

            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            ldx #15
.g1         sta WSYNC
            dex
            bne .g1

            ldy #0
.overRow    lda OverR0,y
            sta TempVar
            ldx #5
.overSc     sta WSYNC
            lda TempVar
            sta PF0
            lda OverR1,y
            sta PF1
            lda OverR2,y
            sta PF2
            dex
            bne .overSc
            iny
            cpy #8
            bne .overRow

            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2
            ldx #47
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

            ldy #63             ; 63 + 1 VBLANK-off = 64 top
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
            ; If past screen edge, hide ship
            cmp #156
            bcc .shipVisible
            ; Ship off-screen — position at 0 but don't draw
            lda #0
            sta TgtLive         ; reuse as "ship visible" flag
            jmp .doPos
.shipVisible
            sta TgtLive         ; nonzero = visible
.doPos
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

            ; Top blank: 59 lines (+ 1 VBLANK-off line = 60)
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
LvlDirX     .byte $00,$01,$FF,$01,$FF,$01,$FF,$01
LvlDirY     .byte $00,$00,$01,$FF,$01,$FF,$01,$FF

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

MelodyNotes .byte 8,9,11,12,15,17,20,24
MelodyVols  .byte 12,11,10,9,8,7,5,3

; Victory jingle - ascending major arpeggio with flourish (12 notes)
VictoryNotes .byte 20,17,15,12,10,8,6,8,6,4,6,4
VictoryVols  .byte 8,9,10,11,12,12,13,12,13,14,12,10

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
GameR0      .byte $C0,$40,$40,$40,$40,$40,$C0,$C0
GameR1      .byte $92,$2B,$2B,$BA,$AA,$AA,$AA,$AA
GameR2      .byte $1D,$05,$05,$1D,$05,$05,$1D,$1D
OverR0      .byte $C0,$40,$40,$40,$40,$40,$C0,$C0
OverR1      .byte $AB,$AA,$AA,$AB,$AA,$92,$93,$93
OverR2      .byte $1D,$14,$14,$1D,$0C,$14,$15,$15

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
