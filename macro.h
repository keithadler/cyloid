; MACRO.H
; Version 1.06, 04/SEP/2009
; Macros used in Atari 2600 programming

;-------------------------------------------------------------------------------
; SLEEP duration
; Original author: Thomas Jentzsch
; Inserts code which takes the specified number of cycles to execute.

            MAC SLEEP
                IF {1} = 1
                    ECHO "MACRO ERROR: 'SLEEP': Duration must be > 1"
                    ERR
                ENDIF
                IF {1} & 1
                    nop $00
                    REPEAT ({1}-3)/2
                        nop
                    REPEND
                ELSE
                    REPEAT ({1})/2
                        nop
                    REPEND
                ENDIF
            ENDM

;-------------------------------------------------------------------------------
; VERTICAL_SYNC
; Original author: Andrew Davie
; Inserts the code required for a proper 3 scanline vertical sync sequence.

            MAC VERTICAL_SYNC
                lda #$02        ; LoaD Accumulator with 2
                ldx #49         ; LoaD X with 49
                sta WSYNC       ; Wait for SYNC (halts CPU until end of scanline)
                sta VSYNC       ; Accumulator D1 bit ON = VSYNC ON
                stx TIM64T      ; set timer to go off in 41 scanlines (49 * 64) / 76
                sta WSYNC       ; first scanline of VSYNC
                sta WSYNC       ; second scanline of VSYNC
                lda #0          ; LoaD Accumulator with 0
                sta WSYNC       ; third scanline of VSYNC
                sta VSYNC       ; Accumulator D1 bit OFF = VSYNC OFF
            ENDM

;-------------------------------------------------------------------------------
; CLEAN_START
; Original author: Andrew Davie
; Standardized initialization of the Atari 2600.

            MAC CLEAN_START
                sei
                cld
                ldx #0
                txa
                tay
.CLEAR_STACK    dex
                txs
                pha
                bne .CLEAR_STACK
            ENDM
