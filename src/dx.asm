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
; status bar and sky gradient (color hardware, levels): the game never touches C524-C5FF
DEF wDx      EQU $C524             ; 1 = line effects active in this scene
DEF wStep    EQU $C525             ; next gradient step
DEF wGrad    EQU $C526             ; 2 bytes: gradient steps of the scene (0 = none)
DEF wPalXi   EQU $C528             ; index of palette X (icon and gauge) for rBCPS, auto-increment
DEF wPalX    EQU $C530             ; 8 bytes: the scenery colors of palette X
DEF wGradBuf EQU $C540             ; gradient steps of the scene (3 bytes each, $FF at the end)
DEF wNight    EQU $C570             ; line 15 work in bank EXTRA_BANK: bit 0 = night falls (3-1), bit 1 = bar to be armed
DEF wPhase   EQU $C571             ; current night step ($FF = to be set)
DEF rSTAT    EQU $FF41
DEF rLYC     EQU $FF45
DEF rLY      EQU $FF44
DEF HUD_LINE EQU 143              ; last visible line: the bar gets its colors back during its horizontal blank.
                                   ; Done before line 145, which the game waits for to turn the screen off ($0EB8).

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

IF HUD_ON
SECTION "hook_stat80", ROM0[$0E18]
    jp DxSplit                     ; replaces: ldh a,[$FF97] / ldh [$FF43],a / pop af / reti (normal level)
SECTION "hook_stat08", ROM0[$0E1E]
    jp DxBoss                      ; replaces: ldh a,[rLCDC] / and $FD / ldh [rLCDC],a / pop af / reti (Jack's room)
SECTION "hook_lyc", ROM0[$07F8]
    call FixLyc                    ; replaces: ld a,$0F / ldh [rLYC],a (every frame, after the game's work)
    nop
ENDC

SECTION "hook_obj", ROM0[$100E]
    call ObjFlags                  ; replaces: ldh [$FF83],a / ld d,$00
    nop

IF HUD_ON
SECTION "dxfix", ROM0[$0018]              ; rst $18-$38 vectors: empty ($FF) in the game, never called
; The game resets its split line (15) after each frame's work: not while the line chain is running
FixLyc:
    ld a, [wDx]
    and a
    jr z, .w
    ld a, [wStep]
    inc a
    ret nz                         ; a line of the chain is still to come in this frame
.w:
    ld a, $0F
    ldh [rLYC], a
    ret
DxFixEnd:
    ASSERT DxFixEnd <= $0040

SECTION "dxnight", ROM0[$0028]             ; rst $28-$38 vectors: empty ($FF) in the game, never called
; Line 15: if night falls in this level, go through bank EXTRA_BANK to advance one step; then the chain.
NightStep:
    ld a, [wNight]
    and a
    jr z, NightDone
    ldh a, [hBank]
    push af
    ld a, EXTRA_BANK
    ldh [hBank], a                 ; first the marker, then the bank
    ld [$2000], a
    call PhaseCheck
    pop af
    ldh [hBank], a
    jr NightRest
    ASSERT @ <= $0040
SECTION "dxnight2", ROM0[$0013]
NightRest:
    ld [$2000], a
    jr NightDone
    ASSERT @ <= $0018
SECTION "dxnight3", ROM0[$000B]
NightDone:
    jp NextLyc
    ASSERT @ <= $0010

SECTION "dxstat", ROM0[$0061]
; Line interrupt: only two branches of the game's handler ($0E0D) are hooked, AF already pushed.
; The game's own line effects (level openings, title cards) therefore keep their exact timing.
; Normal level: the game splits the screen at line 15 (fixed bar above, scrolling scenery below). In addition, on
; color hardware: at line 15 palette X gets its scenery colors back; then the steps of the sky gradient;
; then, at the end of the picture, palette X gets the colors of the bar again.
DxSplit:
    ldh a, [rLYC]
    cp $0F
    jr nz, .other
    ldh a, [$FF97]                 ; original work: scroll the scenery under the bar
    ldh [$FF43], a
    ld a, [wDx]
    and a
    jr z, .done
    push bc
    push hl
    ld a, [wPalXi]
    ldh [rBCPS], a
    ld hl, wPalX
    ld c, LOW(rBCPD)
    call WaitH0
REPT 8
    ld a, [hl+]
    ldh [c], a
ENDR
    xor a
    ld [wStep], a
    push de
    call NightStep
    pop de
    pop hl
    pop bc
.done:
    pop af
    reti
.other:
    ld a, [wDx]
    and a
    jr z, .orig
    ld a, [wStep]
    inc a
    jp nz, DxStatStep              ; a line of our chain
.orig:
    ldh a, [$FF97]                 ; not ours: original work
    ldh [$FF43], a
    jr .done
DxBoss:                            ; Jack's room: the game turns characters off at line 128; palette X is free
    ldh a, [rLCDC]
    and $FD
    ldh [rLCDC], a
    ld a, [wDx]
    and a
    jr z, DxSplit.done
    push bc
    push de
    push hl
    call HudWrite
    pop hl
    pop de
    pop bc
    jr DxSplit.done
WaitH0:                            ; wait for a horizontal or vertical blank (palettes accessible)
    ldh a, [rSTAT]
    and 2
    jr nz, WaitH0
    ret
HudCols:
    HudColsData
GaugeTab:
    GaugeData
GradPtr:                           ; HL = current gradient step (wGradBuf + 3*wStep)
    ld a, [wStep]
    ld l, a
    add a, a
    add a, l
    add a, LOW(wGradBuf)
    ld l, a
    ld h, HIGH(wGradBuf)
    ret

DxStatEnd:
    ASSERT DxStatEnd <= $0100
ENDC

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
IF HUD_ON
    ld a, EXTRA_BANK
    ldh [hBank], a
    ld [$2000], a
    call ExtraApply                ; extra retouches, stored in another bank
    call DxSetup
ENDC
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

IF HUD_ON
; Colors of the bar in palette X (icon, gauge according to energy). Waits until palettes are accessible.
HudWrite:
    ld a, [$C0C8]
    cp 5
    jr c, .e
    ld a, 4
.e:
    add a, a
    ld e, a
    ld d, 0
    ld hl, GaugeTab
    add hl, de
    ld a, [hl+]
    ld e, a
    ld d, [hl]
    ld a, [wPalXi]
    ldh [rBCPS], a
    ld hl, HudCols
    ld c, LOW(rBCPD)
    call WaitH0
    ld a, [hl+]
    ldh [c], a
    ld a, [hl+]
    ldh [c], a
    ld a, [hl+]
    ldh [c], a
    ld a, [hl+]
    ldh [c], a
    ld a, e
    ldh [c], a
    ld a, d
    ldh [c], a
    inc hl
    inc hl
    ld a, [hl+]
    ldh [c], a
    ld a, [hl]
    ldh [c], a
    ret

DxStatStep:                        ; one gradient step, or the bar (end of the picture)
    push bc
    push hl
    call GradPtr
    ld a, [hl+]
    cp $FF
    jr z, .hud
    ld a, $80                      ; palette 0, color 0: the sky
    ldh [rBCPS], a
    ld c, LOW(rBCPD)
    call WaitH0
    ld a, [hl+]
    ldh [c], a
    ld a, [hl+]
    ldh [c], a
    ld a, [wStep]
    inc a
    ld [wStep], a
    ld a, [hl]                     ; line of the next step (or $FF)
    ld b, a
    cp $FF
    jr z, .slow
    ldh a, [rLY]
    inc a
    cp b
    jr nc, .slow                   ; already passed: full path
    ld a, b
    ldh [rLYC], a
    pop hl
    pop bc
    pop af
    reti
.slow:
    push de
    call NextLyc
    pop de
    jr .out2
.hud:
    push de
    call HudWrite
    pop de
    call ChainEnd
.out2:
    pop hl
    pop bc
    pop af
    reti

; Next line of the chain. If it has already passed (late interrupt): gradient steps are skipped;
; the bar is always written.
NextLyc:
    call GradPtr
.nx:
    ld a, [hl+]
    cp $FF
    jr z, .hud
    ld b, a
    ldh a, [rLY]
    inc a
    cp b
    jr c, ChainEnd.set             ; LY+1 < line: still to come
    inc hl
    inc hl
    ld a, [wStep]
    inc a
    ld [wStep], a
    jr .nx
.hud:
    ldh a, [rLY]
    ld b, HUD_LINE
    cp b
    jr c, ChainEnd.set
    call HudWrite                  ; already in vertical blank: palettes accessible
ChainEnd:                          ; the chain is over: back to the game's line 15
    ld a, $FF
    ld [wStep], a
    ld b, $0F
.set:
    ld a, b
    ldh [rLYC], a
    ret

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

IF HUD_ON
SECTION "dx4", ROMX[$65C0], BANK[EXTRA_BANK]
; A scene is turned back on (screen off): prepare the icon, the gauge and the gradient
DxSetup:
    ld a, $FF
    ld [wGradBuf], a
    ld [wStep], a                  ; chain at rest
    xor a
    ld [wDx], a
    ld [wGrad], a
    ld [wGrad+1], a
    ld a, [wScene]
    ld e, a
    ld d, 0
    ld hl, HudXTab
    add hl, de
    ld a, [hl]
    cp $FF
    ret z
    ld [wPhase], a                 ; (kept for a moment: bit 7 = palette X is free in this scenery)
    and $07
    ld b, a                        ; B = palette X
    add a, a
    add a, a
    add a, a
    or $80
    ld [wPalXi], a
    ld c, a
    ld hl, wPalX                   ; keep the scenery colors of palette X
    ld d, 8
.rd:
    ld a, c
    and $3F
    ldh [rBCPS], a
    ldh a, [rBCPD]
    ld [hl+], a
    inc c
    dec d
    jr nz, .rd
    ld a, 2                        ; the icon and the gauge will take palette X at the first line 15 of the level:
    ld [wNight], a                  ; during the level opening, the scenery keeps its colors in palette X
    ld a, [wPhase]
    bit 7, a
    jr z, .later
    call ArmHud                    ; palette X free in this scenery (Batwing, bell tower, Jack's room): bar armed right away
    call HudWrite
.later:
    ld hl, GradList
.gl:
    ld a, [hl+]
    cp $FF
    jr z, .gdone
    ld b, a
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld d, a
    ld a, [wScene]
    cp b
    jr nz, .gl
    ld h, d                        ; copy the steps to RAM (read during the interrupt, whatever the bank)
    ld l, c
    ld de, wGradBuf
.gc:
    ld a, [hl+]
    ld [de], a
    inc de
    cp $FF
    jr z, .gf
    ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl+]
    ld [de], a
    inc de
    jr .gc
.gf:
    ld a, LOW(wGradBuf)
    ld [wGrad], a
    ld a, HIGH(wGradBuf)
    ld [wGrad+1], a
.gdone:
    ld a, [wScene]
    cp NIGHT_SCENE
    jr nz, .nonight
    ld a, [wNight]
    or 1
    ld [wNight], a
    ld a, $FF
    ld [wPhase], a
    call NightPhase
.nonight:
    ld a, 1
    ld [wDx], a
    ret

; Night falls: the step depends on the level page ($FF98). At each new step, the colors of the gradient steps
; slide one notch along the ramp (from yellow to night) and the waves follow. Bank EXTRA_BANK.
PhaseCheck:                        ; called at line 15 when wNight is not zero (bit 1: bar to be armed, bit 0: night)
    ld a, [wNight]
    bit 1, a
    call nz, ArmHud
    ld a, [wNight]
    bit 0, a
    ret z
NightPhase:
    ldh a, [$FF98]
    cp NIGHT_PAGES
    jr c, .ok
    ld a, NIGHT_PAGES-1
.ok:
    ld e, a
    ld d, 0
    ld hl, NightPages
    add hl, de
    ld a, [hl]                     ; offset in the ramp
    ld hl, wPhase
    cp [hl]
    ret z
    ld [hl], a
    add a, a
    ld e, a                        ; DE = 2 * offset
    push de
    ld hl, NightRamp
    add hl, de
    ld de, wGradBuf+1
    ld b, NIGHT_STEPS
.c:
    ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl+]
    ld [de], a
    inc de
    inc de
    dec b
    jr nz, .c
    pop de
    ld hl, NightRamp
    add hl, de
    ld a, [hl+]
    ld b, a
    ld c, [hl]                     ; BC = first sky color = hollow of the waves
    ld hl, NightWaves
    add hl, de
    ld a, $88                      ; palette 1, colors 0 and 1
    ldh [rBCPS], a
    call WaitH0
    ld a, b
    ldh [rBCPD], a
    ld a, c
    ldh [rBCPD], a
    ld a, [hl+]
    ldh [rBCPD], a
    ld a, [hl]
    ldh [rBCPD], a
    ld hl, NightWindows            ; city windows: palette 0, colors 2 and 3 (two groups of buildings)
    add hl, de
    add hl, de
    ld a, $84
    ldh [rBCPS], a
    call WaitH0
    ld b, 4
.f:
    ld a, [hl+]
    ldh [rBCPD], a
    dec b
    jr nz, .f
    ret
; The Batman icon and the gauge switch to palette X (5 cells of the bar). Outside the drawing of a line.
ArmHud:
    ld a, [wNight]
    and $FD
    ld [wNight], a
    ld a, [wPalXi]
    rrca
    rrca
    rrca
    and $07
    ld b, a                        ; B = palette X
    ldh a, [rVBK]
    push af                        ; the interrupted code may be writing attributes
    call WaitH0
    ld a, 1
    ldh [rVBK], a
    ld a, b
    ld [$9800+32+13], a            ; Batman icon
    ld hl, $9800+32+16             ; gauge (4 cells)
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    pop af
    ldh [rVBK], a
    ret
NightWindows:
    NightWindowsData
NightPages:
    NightPagesData
NightRamp:
    NightRampData
NightWaves:
    NightWavesData

; Extra retouches (same format as the scene's own), in bank EXTRA_BANK, already selected
ExtraApply:
    ld a, [wScene]
    cp NB_SCENES
    ret nc
    add a, a
    ld e, a
    ld d, 0
    ld hl, ExtraTab
    add hl, de
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    or h
    ret z
.l:
    ld a, [hl+]
    and a
    ret z
    ld b, a
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
.c:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .c
    jr .l

HudXTab:
    HudXData
GradList:
    GradListData
ExtraTab:
    ExtraData
Dx4End:
    ASSERT Dx4End <= $8000
ENDC
