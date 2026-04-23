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
            lda #2
            sta VSYNC
            sta WSYNC
            sta WSYNC
            sta WSYNC
            lda #0
            sta VSYNC
            lda #2
            sta VBLANK
            lda #44             ; slightly more VBLANK time
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
            sta NumTgts         ; Bug 9: clear before SetupLevel
            lda #2
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
            ; OPT 1: Single joystick read, minimal branching
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
            ; OPT 3: Detect movement from direction bits directly
            lda TempVar
            and #%11110000
            cmp #%11110000      ; all high = no movement
            beq .notMoving
            lda #1
            sta Moving
.notMoving

            ; OPT 4: Simplified fire - fewer stores
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
            adc #2              ; center 4-wide missile on 8px tank
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

            ; Missile movement - OPT 5: use jump table approach
            lda MissileOn
            bne .mGo
            jmp .noMsl
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
            jmp .noMsl

            ; OPT 6: Hit check - only check if missile active (already gated above)
.mHit       ldx #0
.hitLoop    cpx NumTgts
            bcs .noMsl
            lda TgtALive,x
            cmp #1
            bne .hitNext
            ; Y distance
            lda MissileY
            sec
            sbc TgtAY,x
            bcs .hy
            eor #$FF
            adc #1
.hy         cmp #12
            bcs .hitNext
            ; X distance
            lda MissileX
            sec
            sbc TgtAX,x
            bcs .hx
            eor #$FF
            adc #1
.hx         cmp #12
            bcs .hitNext
            ; HIT
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
            jmp .noMsl
.hitNext    inx
            cpx NumTgts
            bcc .hitLoop
.noMsl

            ; OPT 7: Combined death timer + alive check + level check
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
            ; Silence all sounds before score screen
            lda #0
            sta SndVol
            sta SndType
            sta AUDV0
            sta AUDV1
            jmp .afterMove
.noLvlAdv

            ; OPT 8: Move targets only every 4th frame (all levels)
            lda FrameCount
            and #3
            bne .afterMove
            jsr MoveTargets
.afterMove

            ; OPT 9: Inline flicker select (save JSR/RTS = 12 cycles)
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

            ; Collision
            lda HitFlash
            bne .skipC
            lda CXP0FB
            bmi .doDeath
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

            ; OPT 10: Minimal sound - just decay, skip movement sound writes when not moving
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
            ; Movement sound - only write registers when state changes
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
.silence    sta AUDV1           ; A=0 from beq
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
            sta WSYNC
            lda #0
            sta VBLANK
            lda GameMode
            cmp #MODE_PLAY
            beq .g
            cmp #MODE_OVER
            beq .o
            cmp #MODE_LVLUP
            beq .lv
            cmp #MODE_SCORE
            beq .sc
            jmp DrawTitle
.g          jmp DrawGame
.o          jmp DrawOver
.lv         jmp DrawDigitScreen
.sc         jmp DrawDigitScreen

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
            ora FieldColor
            sta COLUBK
            jmp .colorDone
.nc         lda #$9E
            sta COLUP0
            lda FieldColor
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
            cpx #7
            bne .topBorder

            ; Set field colors, then WSYNC to apply cleanly
            lda FieldColor
            sta COLUBK
            lda WallColor
            ora #$08
            sta COLUPF
            sta WSYNC           ; this line shows field color
            inx                 ; X=8

            lda TankY
            clc
            adc #TANK_H
            sta TempVar

            ; 2-line kernel
.fLoop
            txa
            and #$1F
            sec
            sbc #$18
            bcc .obsOff
            txa
            lsr
            lsr
            lsr
            lsr
            lsr
            and #3
            tay
            lda ObsPF1,y
            sta PF1
            lda ObsPF2,y
            sta PF2
            jmp .obsDone
            ; Opt 3: obsOff falls through to obsDone
.obsOff     lda #0
            sta PF1
            sta PF2
.obsDone
            cpx TankY
            bcc .noTank
            cpx TempVar
            bcs .noTank
            txa
            sec
            sbc TankY
            tay
            lda TankGfxBuf,y
            sta GRP0
            inx
            sta WSYNC
            jmp .line2
.noTank     lda #0
            sta GRP0
            inx
            sta WSYNC
.line2
            lda TgtLive
            beq .noTgt
            txa
            sec
            sbc TgtY
            cmp #6
            bcs .noTgt
            tay
            ; Dying targets use explosion graphics
            lda TgtLive
            cmp #2
            bcs .tgtExplode
            lda TargetGfx,y
            jmp .storeTgt
.tgtExplode
            ; Random explosion pattern
            tya
            eor FrameCount
            eor TgtLive
.storeTgt   sta GRP1
            jmp .tgtDone
.noTgt      lda #0
            sta GRP1
.tgtDone
            lda MissileOn
            beq .noMsl
            txa
            sec
            sbc MissileY
            bcc .noMsl
            cmp #4
            bcs .noMsl
            lda #2
            sta ENAM0
            jmp .mslDone
.noMsl      lda #0
            sta ENAM0
.mslDone
            inx
            cpx #184
            beq .fEnd
            sta WSYNC
            jmp .fLoop
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
            lda #2
            sta VBLANK
            lda #0
            sta GRP0
            sta GRP1
            sta ENAM0
            sta ENABL           ; Bug 7: clear ball object
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
            ldy #68
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
            lda #$00
            sta COLUBK
            lda #%00000001      ; REFLECT mode for asymmetric
            sta CTRLPF
            lda #0
            sta PF0
            sta PF1
            sta PF2

            ldy #68
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

            ldy #68
.bot        sta WSYNC
            dey
            bne .bot
            jmp DoOverscan

RenderCyloid SUBROUTINE
            lda #$00
            sta COLUBK
            lda #%00000001      ; REFLECT mode (needed for asymmetric trick)
            sta CTRLPF
            lda #0
            sta PF0
            sta PF1
            sta PF2

            ; Top blank: 68 lines
            ldy #68
.top        sta WSYNC
            dey
            bne .top

            ; Asymmetric PF kernel: 8 rows x 7 scanlines = 56 lines
            ldy #0              ; row index
.row
            ; Set color per row (cycling)
            lda FrameCount
            lsr
            and #$0E
            ora #$C2
            sta COLUPF

            ldx #7              ; 7 scanlines per row
.scanLine
            sta WSYNC
            ; --- LEFT HALF: write PF0/PF1/PF2 early ---
            lda CycLPF0,y       ; 4
            sta PF0              ; 3  = 7 (PF0 drawn at cycle ~23, plenty of time)
            lda CycLPF1,y       ; 4
            sta PF1              ; 3  = 14
            lda CycLPF2,y       ; 4
            sta PF2              ; 3  = 21
            ; --- WAIT for beam to pass PF0 right half (cycle ~53) ---
            ; We're at ~21 cycles. Need to reach ~40 before writing right PF2.
            ; PF2 right starts at cycle ~40 (pixel 148), so write before that.
            ; Actually in repeat mode, right PF0 starts at cycle 37.
            ; We need to update PF0 for right half AFTER left PF2 is latched
            ; but BEFORE right PF0 is drawn.
            ;
            ; Timing: left PF2 finishes at cycle ~36. Right PF0 starts at ~37.
            ; So we need to write right-half PF0 between cycle 36-37... impossible
            ; in repeat mode. 
            ;
            ; In REFLECT mode, right half draws PF2,PF1,PF0 (reversed order).
            ; So right PF2 starts at ~37, PF1 at ~49, PF0 at ~65.
            ; We can update PF2 after left PF2 latches (~36), then PF1, then PF0.
            ;
            ; USE REFLECT MODE for the asymmetric trick!
            ; Left: PF0(23) PF1(29) PF2(36)
            ; Right: PF2(37) PF1(49) PF0(65)
            ; After writing left PF2 at cycle 21, wait until cycle ~37,
            ; then write right PF2, then PF1, then PF0.
            
            ; Timing: left PF2 latched at cycle ~36, right PF2 at ~44
            ; We're at cycle ~21 after writing left PF2.
            ; Need to wait until cycle ~42 before writing right PF2.
            ; Burn 21 cycles (10.5 NOPs, use 10 NOPs + 1 extra cycle)
            nop                  ; 2 = 23
            nop                  ; 2 = 25
            nop                  ; 2 = 27
            nop                  ; 2 = 29
            nop                  ; 2 = 31
            nop                  ; 2 = 33
            nop                  ; 2 = 35
            nop                  ; 2 = 37
            nop                  ; 2 = 39
            nop                  ; 2 = 41
            ; --- RIGHT HALF: update PF2 first (draws first in reflect) ---
            lda CycRPF2,y       ; 4 = 45  (right PF2 latches at ~44, just in time)
            sta PF2              ; 3 = 48
            lda CycRPF1,y       ; 4 = 52  (right PF1 at ~52)
            sta PF1              ; 3 = 55
            lda CycRPF0,y       ; 4 = 59  (right PF0 at ~60)
            sta PF0              ; 3 = 62

            dex
            bne .scanLine

            ; Gap line: clear PF
            sta WSYNC
            lda #0
            sta PF0
            sta PF1
            sta PF2

            iny
            cpy #8
            bne .row

            ; Bottom blank: 68 lines
            ldy #68
.bot        sta WSYNC
            dey
            bne .bot

            jmp DoOverscan

RenderBlack SUBROUTINE
            lda #0
            sta COLUBK
            sta COLUPF
            sta PF0
            sta PF1
            sta PF2
            ldx #192
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
