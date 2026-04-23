; VCS.H
; Version 1.05, 13/November/2003

VERSION_VCS = 105

; THIS IS A PRELIMINARY RELEASE OF *THE* "STANDARD" VCS.H
; THIS FILE IS EXPLICITLY SUPPORTED AS A ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE
; ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE
; ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE
; ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE
; ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE ACTIVE
; Please contribute to this file, and report all bugs/issues to the
; Stella mailing list (stella@biglist.com).

; TIA REGISTERS (active active active active active active active active)

VSYNC   =  $00  ; 0000 00x0   Vertical Sync Set-Clear
VBLANK  =  $01  ; xx00 00x0   Vertical Blank Set-Clear
WSYNC   =  $02  ; ---- ----   Wait for Horizontal Blank
RSYNC   =  $03  ; ---- ----   Reset Horizontal Sync Counter
NUSIZ0  =  $04  ; 00xx 0xxx   Number-Size player/missile 0
NUSIZ1  =  $05  ; 00xx 0xxx   Number-Size player/missile 1
COLUP0  =  $06  ; xxxx xxx0   Color-Luminance Player 0
COLUP1  =  $07  ; xxxx xxx0   Color-Luminance Player 1
COLUPF  =  $08  ; xxxx xxx0   Color-Luminance Playfield
COLUBK  =  $09  ; xxxx xxx0   Color-Luminance Background
CTRLPF  =  $0A  ; 00xx 0xxx   Control Playfield, Ball, Collisions
REFP0   =  $0B  ; 0000 x000   Reflection Player 0
REFP1   =  $0C  ; 0000 x000   Reflection Player 1
PF0     =  $0D  ; xxxx 0000   Playfield Register Byte 0
PF1     =  $0E  ; xxxx xxxx   Playfield Register Byte 1
PF2     =  $0F  ; xxxx xxxx   Playfield Register Byte 2
RESP0   =  $10  ; ---- ----   Reset Player 0
RESP1   =  $11  ; ---- ----   Reset Player 1
RESM0   =  $12  ; ---- ----   Reset Missile 0
RESM1   =  $13  ; ---- ----   Reset Missile 1
RESBL   =  $14  ; ---- ----   Reset Ball
AUDC0   =  $15  ; 0000 xxxx   Audio Control 0
AUDC1   =  $16  ; 0000 xxxx   Audio Control 1
AUDF0   =  $17  ; 000x xxxx   Audio Frequency 0
AUDF1   =  $18  ; 000x xxxx   Audio Frequency 1
AUDV0   =  $19  ; 0000 xxxx   Audio Volume 0
AUDV1   =  $1A  ; 0000 xxxx   Audio Volume 1
GRP0    =  $1B  ; xxxx xxxx   Graphics Register Player 0
GRP1    =  $1C  ; xxxx xxxx   Graphics Register Player 1
ENAM0   =  $1D  ; 0000 00x0   Graphics Enable Missile 0
ENAM1   =  $1E  ; 0000 00x0   Graphics Enable Missile 1
ENABL   =  $1F  ; 0000 00x0   Graphics Enable Ball
HMP0    =  $20  ; xxxx 0000   Horizontal Motion Player 0
HMP1    =  $21  ; xxxx 0000   Horizontal Motion Player 1
HMM0    =  $22  ; xxxx 0000   Horizontal Motion Missile 0
HMM1    =  $23  ; xxxx 0000   Horizontal Motion Missile 1
HMBL    =  $24  ; xxxx 0000   Horizontal Motion Ball
VDELP0  =  $25  ; 0000 000x   Vertical Delay Player 0
VDELP1  =  $26  ; 0000 000x   Vertical Delay Player 1
VDELBL  =  $27  ; 0000 000x   Vertical Delay Ball
RESMP0  =  $28  ; 0000 00x0   Reset Missile 0 to Player 0
RESMP1  =  $29  ; 0000 00x0   Reset Missile 1 to Player 1
HMOVE   =  $2A  ; ---- ----   Apply Horizontal Motion
HMCLR   =  $2B  ; ---- ----   Clear Horizontal Move Registers
CXCLR   =  $2C  ; ---- ----   Clear Collision Latches

;-------------------------------------------------------------------------------
; TIA READ REGISTERS

CXM0P   =  $30  ;xx00 0000   Read Collision  M0-P1   M0-P0
CXM1P   =  $31  ;xx00 0000                   M1-P0   M1-P1
CXP0FB  =  $32  ;xx00 0000                   P0-PF   P0-BL
CXP1FB  =  $33  ;xx00 0000                   P1-PF   P1-BL
CXM0FB  =  $34  ;xx00 0000                   M0-PF   M0-BL
CXM1FB  =  $35  ;xx00 0000                   M1-PF   M1-BL
CXBLPF  =  $36  ;x000 0000                   BL-PF   -----
CXPPMM  =  $37  ;xx00 0000                   P0-P1   M0-M1
INPT0   =  $38  ;x000 0000   Read Pot Port 0
INPT1   =  $39  ;x000 0000   Read Pot Port 1
INPT2   =  $3A  ;x000 0000   Read Pot Port 2
INPT3   =  $3B  ;x000 0000   Read Pot Port 3
INPT4   =  $3C  ;x000 0000   Read Input (Trigger) 0
INPT5   =  $3D  ;x000 0000   Read Input (Trigger) 1

;-------------------------------------------------------------------------------
; RIOT REGISTERS

SWCHA   =  $280  ; Port A data register for joysticks (active active active)
SWACNT  =  $281  ; Port A data direction register (DDR)
SWCHB   =  $282  ; Port B data (console switches)
SWBCNT  =  $283  ; Port B DDR
INTIM   =  $284  ; Timer output
TIMINT  =  $285  ; Timer Interrupt

TIM1T   =  $294  ; set 1 clock interval
TIM8T   =  $295  ; set 8 clock interval
TIM64T  =  $296  ; set 64 clock interval
T1024T  =  $297  ; set 1024 clock interval
