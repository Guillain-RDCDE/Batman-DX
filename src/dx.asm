; Batman DX - Game Boy Color colorization of Batman: The Video Game (Sunsoft, 1990)
; Assembled over the original ROM (rgblink -O). See TECHNICAL.md.
;
; How it works:
;  - the game never touches its palettes (BGP=E4, OBP0=E4, OBP1=1B): there is no fade to follow.
;  - scenery: one "tile -> palette" table per scene, copied to RAM (wTab). Attributes are written
;      * all at once each time the screen is turned back on (6 places, rst $08),
;      * on the fly in the screen command runner ($0EF9), the only path while the screen is on.
;
;    boss flashing (OBP1) becomes "palette 7-p".
;  - on a monochrome Game Boy, all added code is skipped (wIsCGB = 0).

INCLUDE "build/scenes.inc"         ; NB_SCENES, scene tables and scene data (macros)

DEF rLCDC EQU $FF40
DEF rVBK  EQU $FF4F
DEF rBCPS EQU $FF68
DEF rBCPD EQU $FF69
DEF rOCPS EQU $FF6A
DEF rOCPD EQU $FF6B
DEF hBank EQU $FFFD

DEF DXBANK   EQU 6
DEF wIsCGB   EQU $C520             ; 1 = color console
DEF wScene   EQU $C521             ; current scene (index into SceneTable)
DEF wCnt     EQU $C522
DEF wShine   EQU $C523
DEF wTab     EQU $C600             ; tile -> attribute table of the current scene (256 bytes)

; ---------------------------------------------------------------- hooks
SECTION "hook_boot", ROM0[$0100]
    ld e, a                        ; E survives the memory clears
    jp $0150

SECTION "hook_init", ROM0[$0168]
    call DxInit                    ; replaces: xor a / ld [$C0E3],a
    nop

SECTION "rst08", ROM0[$0008]
    jp LcdOn                       ; replaces every "ldh [rLCDC],a" that turns the screen back on

SECTION "rst10", ROM0[$0010]
    jp LcdOnText                   ; same, for text-only screens (Game Over, stage select...)

SECTION "hook_lcd1", ROM0[$0212]
    rst $08
    nop
SECTION "hook_lcd2", ROM0[$04D0]
    rst $10
    nop
SECTION "hook_lcd3", ROM0[$054B]
    rst $10
    nop
SECTION "hook_lcd4", ROM0[$0706]
    rst $08
    nop
SECTION "hook_lcd5", ROM0[$0AA7]
    rst $10
    nop
SECTION "hook_lcd6", ROMX[$6885], BANK[6]
    rst $08
    nop

SECTION "hook_gfxA", ROM0[$0F74]
    call SceneFromA                ; replaces: ld b,$03 / cp $14
    nop
SECTION "hook_gfxB", ROM0[$0FC1]
    call SceneFromB                ; replaces: ld b,$05 / cp $50
    nop

IF SHINE
SECTION "hook_title1", ROM0[$0214]
    call TitleShine                ; replaces: ld hl,$CB00 (logo loop) - nothing is added during play
SECTION "hook_title2", ROM0[$02C6]
    call TitleShine                ; replaces: ld hl,$CB00 (title screen loop)
ENDC

SECTION "hook_cmd", ROM0[$0EF9]
    jp CmdHook                     ; replaces: push af / and $3F

SECTION "hook_obj", ROM0[$100E]
    call ObjFlags                  ; replaces: ldh [$FF83],a / ld d,$00
    nop

; ---------------------------------------------------------------- code in bank 0
SECTION "dx0", ROM0[$3B55]
DxInit:
    ld a, e
    cp $11
    ld a, 0
    jr nz, .mono
    inc a
.mono:
    ld [wIsCGB], a
    xor a
    ld [wScene], a
    ld [$C0E3], a                  ; original instruction
    ret

SceneFromA:                        ; A = graphics sheet number (banks 3-4)
    push af
    cp NB_GFX_A
    jr nc, .no
    push hl
    ld hl, SceneTabA
    jr SceneCommon
.no:
    pop af
    ld b, $03
    cp $14
    ret
SceneFromB:                        ; A = graphics sheet number (banks 5-7)
    push af
    cp NB_GFX_B
    jr nc, .no
    push hl
    ld hl, SceneTabB
    add a, l
    ld l, a
    jr nc, .ok
    inc h
.ok:
    ld a, [hl]
    cp $FF
    jr z, .keep
    ld [wScene], a
.keep:
    pop hl
.no:
    pop af
    ld b, $05
    cp $50
    ret
SceneCommon:
    add a, l
    ld l, a
    jr nc, .ok
    inc h
.ok:
    ld a, [hl]
    cp $FF
    jr z, .keep
    ld [wScene], a
.keep:
    pop hl
    pop af
    ld b, $03
    cp $14
    ret

ObjFlags:                          ; bit 4 (OBP1 = flashing) -> palette 7-p
    bit 4, a
    jr z, .s
    or $07
.s:
    ldh [$FF83], a
    ld d, $00
    ret

LcdOnText:
    push af
    xor a
    ld [wScene], a                 ; scene 0 = text
    pop af
LcdOn:                             ; A = value meant for rLCDC
    push af
    bit 7, a
    jr z, .set
    ldh a, [rLCDC]
    rlca
    jr c, .set                     ; already on
    ld a, [wIsCGB]
    and a
    jr z, .set
    push bc
    push de
    push hl
    ldh a, [hBank]
    push af
    ld a, DXBANK
    ldh [hBank], a                 ; flag first, then the bank: safe if an interrupt hits in between
    ld [$2000], a
    call SceneApply
    pop af
    ldh [hBank], a
    ld [$2000], a
    pop hl
    pop de
    pop bc
.set:
    pop af
    ldh [rLCDC], a
    ret

OrigCmd:
    push af
    and $3F
    jp $0EFC

CmdHook:                           ; A = type<<6 | count, HL = destination, DE = source
    push af
    ld a, [wIsCGB]
    and a
    jr z, .plain
    ldh a, [rLCDC]
    rlca
    jr nc, .plain                  ; screen off: the sweep at turn-on will do the work
    ld a, h
    cp $98
    jr c, .plain
    jr nz, .not98
    ld a, l
    cp $40
    jr c, .plain                   ; two top rows (status bar): fixed attributes
    jr .color
.not98:
    cp $9C
    jr c, .color
.plain:
    pop af
    jr OrigCmd
.color:
    pop af
    cp $90
    jp z, Column
    push hl
    push de
    push af
    call OrigCmd                   ; the tiles, through the original routine
    pop af
    pop de
    pop hl
    ld b, a
    and $3F
    ld [wCnt], a
    ld a, 1
    ldh [rVBK], a
    ld a, b
    ld b, HIGH(wTab)
    rlca
    rlca
    and $03
    jr z, .t0
    dec a
    jr z, .t1
    dec a
    jr z, .t2
    ; type 3: one tile repeated down a column
    ld a, [de]
    inc de
    ld c, a
    ld a, [bc]
    ld c, a
    ld a, [wCnt]
    ld b, a
.l3:
    ld [hl], c
    ld a, l
    add a, $20
    ld l, a
    jr nc, .n3
    inc h
.n3:
    dec b
    jr nz, .l3
    jr .end
.t0:                               ; type 0: row -> jump into an unrolled run (10 cycles per tile)
    ld a, [wCnt]
    cp 25
    jr nc, .t0slow
    ld c, a
    add a, a
    add a, a
    add a, c                       ; 5 bytes of code per tile
    cpl
    inc a
    add a, LOW(RowEnd)
    ld c, a
    ld a, HIGH(RowEnd)
    adc a, $FF
    ld b, a
    push bc
    ld b, HIGH(wTab)
    ret                            ; jumps to RowEnd - 5*count
.t0slow:
    ld a, [de]
    inc de
    ld c, a
    ld a, [bc]
    ld [hl+], a
    ld a, [wCnt]
    dec a
    ld [wCnt], a
    jr nz, .t0slow
    jr .end
.t1:                               ; type 1: one tile repeated along a row
    ld a, [de]
    inc de
    ld c, a
    ld a, [bc]
    ld c, a
    ld a, [wCnt]
    ld b, a
    ld a, c
.l1:
    ld [hl+], a
    dec b
    jr nz, .l1
    jr .end
.t2:                               ; type 2: column
    ld a, [de]
    inc de
    ld c, a
    ld a, [bc]
    ld [hl], a
    ld a, l
    add a, $20
    ld l, a
    jr nc, .n2
    inc h
.n2:
    ld a, [wCnt]
    dec a
    ld [wCnt], a
    jr nz, .t2
.end:
    xor a
    ldh [rVBK], a
    ret

; Scrolling column (16 tiles from row 2): fast path, tiles then palettes
Column:
    ld a, d
    cp $CB
    jr nz, .slow
    ld a, e
    cp $E0
    jr nc, .slow
    ld a, l
    and $E0
    cp $40
    jr nz, .slow
    ld a, h
    cp $98
    jr z, .fast
.slow:
    ld a, $90
    push hl
    push de
    call OrigCmd
    pop de
    pop hl
    ld a, 16
    ld [wCnt], a
    ld a, 1
    ldh [rVBK], a
    ld b, HIGH(wTab)
    jr CmdHook.t2
.fast:
    push hl
    push de
    ld bc, $0020
REPT 16
    ld a, [de]
    inc e
    ld [hl], a
    add hl, bc
ENDR
    pop de
    pop hl
    ld a, 1
    ldh [rVBK], a
    ld b, HIGH(wTab)
FOR I, 16
    ld a, [de]
    inc e
    ld c, a
    ld a, [bc]
    ld [hl], a
    ld a, l
    add a, $20
    ld l, a
IF I == 5 || I == 13
    inc h
ENDC
ENDR
    xor a
    ldh [rVBK], a
    ret

RowUnrolled:
REPT 24
    ld a, [de]
    inc de
    ld c, a
    ld a, [bc]
    ld [hl+], a
ENDR
RowEnd:
    xor a
    ldh [rVBK], a
    ret

IF SHINE
; Title screen: a light band sweeps down the letters (color 3 of palettes 2 to 6), every 4 frames
TitleShine:
    ld a, [wIsCGB]
    and a
    jr z, .fin
    ld a, [wScene]
    dec a
    jr nz, .fin                    ; scene 1 = title
    ld hl, wShine
    inc [hl]
    ld a, [hl]
    and $03
    jr nz, .fin
    ld a, [hl]
    rrca
    rrca
    and $0F                        ; step 0-15
    ld c, a
    add a, a
    add a, a
    add a, c
    add a, a                       ; x10
    ld c, a
    ld b, 0
    ld hl, ShineTab
    add hl, bc
    ld c, $80 + 2*8 + 6
    ld b, 5
.l:
    ldh a, [$FF41]
    and $02
    jr nz, .l                      ; wait for horizontal or vertical blank (palettes accessible)
    ld a, c
    ldh [rBCPS], a
    ld a, [hl+]
    ldh [rBCPD], a
    ld a, [hl+]
    ldh [rBCPD], a
    ld a, c
    add a, 8
    ld c, a
    dec b
    jr nz, .l
.fin:
    ld hl, $CB00
    ret
ShineTab:
    ShineData
ENDC

SceneTabA:
    SceneTabAData
SceneTabB:
    SceneTabBData
Dx0End:
    ASSERT Dx0End <= $4000

; ---------------------------------------------------------------- code and data in bank 6
SECTION "dx6", ROMX[$4CD9], BANK[6]
; Applies the current scene: table to RAM, palettes, attributes of both screen maps. Screen off.
SceneApply:
    ld a, [wScene]
    cp NB_SCENES
    jr c, .ok
    xor a
.ok:
    add a, a
    ld e, a
    ld d, 0
    ld hl, SceneTable
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a                        ; HL -> table (256), background palettes (64), character palettes (64), status bar flag
    ld de, wTab
    ld b, 0
.cp:
    ld a, [hl+]
    ld [de], a
    inc e
    dec b
    jr nz, .cp
    ld a, $80
    ldh [rBCPS], a
    ld b, 64
.bp:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .bp
    ld a, $80
    ldh [rOCPS], a
    ld b, 64
.op:
    ld a, [hl+]
    ldh [rOCPD], a
    dec b
    jr nz, .op
    ld a, [hl+]                    ; palette forced on the two top rows ($FF = none)
    push af
.pl:                               ; retouches: (length, address, bytes)... 0 = end. Redrawn tiles, added text
    ld a, [hl+]
    and a
    jr z, .pdone
    ld b, a
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
.pc:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .pc
    jr .pl
.pdone:
    ld hl, $9800
    ld b, HIGH(wTab)
.sw:
    xor a
    ldh [rVBK], a
    ld c, [hl]
    inc a
    ldh [rVBK], a
    ld a, [bc]
    ld [hl+], a
    ld a, h
    cp $A0
    jr nz, .sw
    pop af
    cp $FF
    jr z, .nohud
    ld hl, $9800
    ld b, $40
.hud:
    ld [hl+], a
    dec b
    jr nz, .hud
.nohud:
    xor a
    ldh [rVBK], a
    ret

SceneTable:
    SceneTableData
    SceneBlocks
Dx6End:
    ASSERT Dx6End <= $6800

SECTION "dx6b", ROMX[$7636], BANK[6]
    SceneBlocks2
