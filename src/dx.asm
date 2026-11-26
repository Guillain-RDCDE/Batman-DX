; Batman DX - Game Boy Color colorization of Batman: The Video Game (Sunsoft, 1990)
; Assembled over the original ROM (rgblink -O). See TECHNICAL.md.
;
; How it works:
;  - the game never touches its palettes (BGP=E4, OBP0=E4, OBP1=1B): there is no fade to follow.
;  - scenery: one "tile -> palette" table per scene, copied to RAM (wTab). Attributes are written
;      * all at once each time the screen is turned back on (6 places, rst $08),
;      * on the fly in the screen command runner ($0EF9), the only path while the screen is on.
;  - characters: the palette (bits 0-2) is written into the pose data by tools/patch_obj.py;
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
; status bar and sky gradient (color console, levels): area C524-C5FF, never touched by the game
DEF wDx      EQU $C524             ; 1 = line effects active in this scene
DEF wStep    EQU $C525             ; next gradient step
DEF wGrad    EQU $C526             ; 2 bytes: gradient steps of the scene (0 = none)
DEF wPalXi   EQU $C528             ; index of palette X (icon and gauge) for rBCPS, auto-increment
DEF wPalX    EQU $C530             ; 8 bytes: the scenery colors of palette X
IF PLUS                            ; Plus edition: a step = line, palette index, target register, 4 bytes
DEF wGradBuf EQU $C580
ELSE
DEF wGradBuf EQU $C540             ; gradient steps of the scene (3 bytes each, $FF at the end)
ENDC
DEF wNight    EQU $C570             ; line 15 work in bank EXTRA_BANK: bit 0 = night falls (3-1), bit 1 = bar to arm, bit 2 = living colors, bit 3 = slow scrolling
DEF wPhase   EQU $C571             ; current night step ($FF = to be set)
DEF wMode    EQU $C542             ; Plus edition: 1 = LevelPatch is called for a broken block (cell in HL)
DEF wRemnant   EQU $C543             ; Plus edition: tile left by the broken block
DEF wLifePtr  EQU $C540             ; Plus edition: address of the living colors table (gradient area of the published edition, free here)
DEF wLife     EQU $C572             ; Plus edition: frame counter, step (0-63) of the living colors, table address (2 bytes)
DEF rSTAT    EQU $FF41
DEF rLYC     EQU $FF45
DEF rLY      EQU $FF44
DEF LEVEL_BANK EQU 9                ; Plus edition: scenery added to the levels
DEF GSTEP EQU 3+4*PLUS              ; size of a gradient step (Plus: line, index, target register, 4 bytes)
DEF wSlow     EQU $C544             ; Plus edition: slow scrolling (last value of $FF97, 2-byte total)
DEF wTplSize    EQU $C547             ; Plus edition: size of a template block (0 = 256)
DEF wLogoPal EQU $C581             ; Plus edition, title screen: 1 = the logo golds are in palettes 1, 3-7
DEF wLogoSave EQU $C582            ; Plus edition, title screen: colors 1-3 of these 6 palettes, saved (36 bytes)
DEF wFade    EQU $C5B1             ; Plus edition, title screen: logo -> title fade (0 = not started, 1-63 running, 64 = done)
DEF wFar     EQU $C548             ; Plus edition: reading routine for bank FAR_BANK, copied here (40 bytes at most)
DEF FAR_BANK EQU 10
DEF HUD_LINE EQU 143              ; last visible line: the bar gets its colors back during its horizontal blank.
                                   ; Done before line 145, which the game polls to turn the screen off ($0EB8).

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
IF PLUS
SECTION "hook_title1", ROM0[$0214]
    call TitleShineL               ; replaces: ld hl,$CB00 (logo loop) - nothing is added during play
SECTION "hook_title2", ROM0[$02C6]
    call TitleShineT               ; replaces: ld hl,$CB00 (title screen loop)
ELSE
SECTION "hook_title1", ROM0[$0214]
    call TitleShine                ; replaces: ld hl,$CB00 (logo loop) - nothing is added during play
SECTION "hook_title2", ROM0[$02C6]
    call TitleShine                ; replaces: ld hl,$CB00 (title screen loop)
ENDC
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
; The game sets its split line (15) back after its frame work: not while our line chain is running
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

SECTION "dxnight", ROM0[$0028]             ; rst vectors $28-$38: empty ($FF) in the game, never called
; Line 15: if night falls in this level, go through bank EXTRA_BANK to move one step; then the chain.
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
; Line interrupt: we only hook two branches of the game's handler ($0E0D), AF already pushed.
; The game's own line effects (level openings, title cards) therefore keep their exact timing.
; Normal level: the game splits the screen at line 15 (fixed bar above, scrolling scenery below). On top of
; that, on a color console: line 15, palette X gets its scenery colors back; then the sky gradient steps;
; then, at the end of the picture, palette X takes the bar colors again.
DxSplit:
    ldh a, [rLYC]
    cp $0F
    jr nz, .other
    ldh a, [$FF97]                 ; original work: scroll the scenery under the bar
    ldh [$FF43], a
    ld a, [wDx]
    and a
    jr z, .fin
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
IF PLUS
    ld a, LOW(wGradBuf)
ELSE
    xor a
ENDC
    ld [wStep], a
    push de
    call NightStep
    pop de
    pop hl
    pop bc
.fin:
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
    jr .fin
DxBoss:                            ; Jack's room: the game turns characters off at line 128; palette X is free
    ldh a, [rLCDC]
    and $FD
    ldh [rLCDC], a
    ld a, [wDx]
    and a
    jr z, DxSplit.fin
    push bc
    push de
    push hl
    call HudWrite
    pop hl
    pop de
    pop bc
    jr DxSplit.fin
WaitH0:                            ; wait for a horizontal or vertical blank (palettes accessible)
    ldh a, [rSTAT]
    and 2
    jr nz, WaitH0
    ret
HudCols:
    HudColsData
GaugeTab:
    GaugeData
IF !PLUS
GradPtr:                           ; HL = current gradient step (wGradBuf + 3*wStep)
    ld a, [wStep]
    ld l, a
    add a, a
    add a, l
    add a, LOW(wGradBuf)
    ld l, a
    ld h, HIGH(wGradBuf)
    ret
ENDC
IF PLUS
; End of level loading: the Plus edition adds pieces of scenery (empty cells only, color console).
LevelPatch:
    ld a, [wIsCGB]
    and a
    jr z, .fin
    ldh a, [hBank]
    push af
    ld a, LEVEL_BANK
    ldh [hBank], a                 ; first the shadow copy, then the bank
    ld [$2000], a
    call LevelDo
    pop af
    ldh [hBank], a
    ld [$2000], a
.fin:
    ld a, [$C0C2]                  ; original instruction
    ret
ENDC
DxStatEnd:
    ASSERT DxStatEnd <= $0100
ENDC

; ---------------------------------------------------------------- code in bank 0
IF PLUS
SECTION "hook_logoraster", ROM0[$0E2A]
    jp LogoRaster                  ; replaces: push hl / ld a,[$C0B8]
SECTION "hook_sound", ROMX[$4009], BANK[2]
    call SoundTMA                    ; replaces: ld a,$BB / ld [hl+],a
ENDC
SECTION "dx0", ROM0[$3B55]
DxInit:
    ld a, e
    cp $11
    ld a, 0
    jr nz, .mono
    inc a
.mono:
    ld [wIsCGB], a
IF PLUS
; Double speed: on a Game Boy Color the Plus edition runs in CGB double speed (the CPU runs twice as fast; picture and
; sound do not change). The work added on every line (parallax, nightfall, gradient) took time from the game: in the
; Batwing stages 2 to 3 % of the frames came late, none in the original. The music timer is adjusted to match
; (SoundTMA).
    and a
    jr z, .slow
    ldh a, [$FF4D]
    rlca
    jr c, .slow                    ; already in double speed
    ld a, $30
    ldh [$FF00], a
    ld a, 1
    ldh [$FF4D], a
    xor a
    ldh [$FFFF], a
    stop
.slow:
ENDC
    xor a
    ld [wScene], a
    ld [$C0E3], a                  ; original instruction
    ret
IF PLUS
LogoRaster:                        ; replaces the logo branch ($0E2A-$0E61) of the game's line handler
; Spinning logo and stage title cards: on every line, SCY for the next line. In double speed the game wrote it in the
; middle of the line (a vertical seam across the logo): wait for the end of the line. Same computation as the game;
; the memory writes come after SCY. Monochrome Game Boy ($FF4D = $FF): no wait, SCY is written within one cycle of
; the original timing.
    push hl
    ld a, [$C0B8]
    and a
    jr nz, .b                      ; blank lines at the top
    ld a, [$C0BA]
    cp $90
    jr nc, .c                      ; blank lines at the bottom
    ld h, a
    ld a, [$C0BB]
    ld l, a
    ld a, [$C0B9]
    add a, l
    ld l, a                        ; L = new fraction
    ld a, [$C0BC]
    adc a, h
    ld h, a                        ; H = new picture line
    ldh a, [$FF4D]
    inc a
    jr nz, .w1                     ; color console (double speed): wait for the end of the line
.ok1:
    ldh a, [$FF45]
    cpl
    inc a
    add a, h
    ldh [$FF42], a                 ; SCY = picture line - LYC
    ld a, l
    ld [$C0B9], a
    ld a, h
    ld [$C0BA], a
    jr .fin
.w1:
    ldh a, [$FF41]
    and 2
    jr nz, .w1                     ; modes 2 and 3 (line being drawn)
    jr .ok1
.b:
    dec a
    ld l, a
    ldh a, [$FF4D]
    inc a
    jr nz, .w2
.ok2:
    ldh a, [$FF45]
    cpl
    inc a
    add a, $90
    ldh [$FF42], a
    ld a, l
    ld [$C0B8], a
    jr .fin
.w2:
    ldh a, [$FF41]
    and 2
    jr nz, .w2
    jr .ok2
.c:
    ldh a, [$FF4D]
    inc a
    jr nz, .w3
.ok3:
    ldh a, [$FF45]
    cpl
    inc a
    add a, $90
    ldh [$FF42], a
.fin:
    ld hl, $FF45
    inc [hl]
    ld a, [hl]
    cp 145
    jr c, .fin2
    ld [hl], 0                     ; last line done: the chain restarts at the top of the next frame, even when the game had
.fin2:                             ; no time to restart it (first frame after power-on: the title screen flashed)
    pop hl
    pop af
    reti
.w3:
    ldh a, [$FF41]
    and 2
    jr nz, .w3
    jr .ok3
SoundTMA:                            ; replaces: ld a,$BB / ld [hl+],a (bank 2, sound start-up: TMA)
    ld a, [wIsCGB]                 ; timer at 4096 Hz, 69 steps: 59.4 Hz; in double speed it counts at 8192 Hz:
    and a                          ; 138 steps for the same tempo
    ld a, $BB
    jr z, .w
    ld a, $76
.w:
    ld [hl+], a
    ret
ENDC

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
IF PLUS
; Plus edition: the title screen work lives in bank EXTRA_BANK (room in bank 0: the metallic gold logo)
TitleShineL:                       ; logo loop
    ld b, 1
    jr TitleCommon
TitleShineT:                       ; title screen loop
    ld b, 0
TitleCommon:
    ldh a, [hBank]
    push af
    ld a, EXTRA_BANK
    ldh [hBank], a                 ; first the marker, then the bank: safe if an interrupt comes
    ld [$2000], a
    call TitleWork
    pop af
    ldh [hBank], a
    ld [$2000], a
    ld hl, $CB00
    ret
ELSE
; Title screen: a light band runs down the letters (color 3 of palettes 2 to 6), every 4 frames
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
ENDC

IF HUD_ON
; Bar colors in palette X (icon, gauge by energy). To be awaited: palettes accessible.
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
IF PLUS
    ; Plus edition: wStep = low byte of the current step's address. Short path: we must arrive DURING the
    ; horizontal blank of the trigger line (about 80 cycles after it starts), otherwise we wait one more line.
    ld a, [wStep]
    ld l, a
    ld h, HIGH(wGradBuf)
    ld a, [hl+]
    cp $FF
    jr z, .hud
    ld a, [hl+]                    ; palette index of the step, target register (rBCPD or SCX), then 4 bytes
    ldh [rBCPS], a
    ld c, [hl]
    inc hl
.w:
    ldh a, [rSTAT]
    and 2
    jr nz, .w
REPT 4
    ld a, [hl+]
    ldh [c], a
ENDR
    ld a, l
    ld [wStep], a
ELSE
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
ENDC
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

; Next line of the chain. If it has already gone by (late interrupt): skip the gradient
; steps; the bar is always written.
NextLyc:
IF PLUS
    ld a, [wStep]
    ld l, a
    ld h, HIGH(wGradBuf)
ELSE
    call GradPtr
ENDC
.nx:
    ld a, [hl+]
    cp $FF
    jr z, .hud
    ld b, a
    ldh a, [rLY]
    inc a
    cp b
    jr c, ChainEnd.set             ; LY+1 < line: still to come
IF PLUS
    ld de, GSTEP-1
    add hl, de
    ld a, l
    ld [wStep], a
ELSE
    inc hl
    inc hl
    ld a, [wStep]
    inc a
    ld [wStep], a
ENDC
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
; Sets up the current scene: table in RAM, palettes, attributes of the whole screen memory. Screen off.
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
IF PLUS
; Broken block: the game puts tile 80 (a corner of a light panel). The Plus edition puts the wall that is behind.
SECTION "hook_block1", ROMX[$457A], BANK[1]
    call Remnant1                    ; A = tile to leave in the level (cell HL)
    jr $458A
SECTION "hook_block2", ROMX[$45C0], BANK[1]
    call Remnant2                    ; the same, for the screen
    jr $45CE
SECTION "dx1", ROMX[$7BFD], BANK[1]
Remnant1:
    ldh a, [$FF9B]
    and $F0
    cp $40
    jr nz, .block
    ldh a, [$FF9B]                 ; item block: the item (original instructions)
    sub $10
    ret
.block:
    ld a, $80                      ; gray console, or unknown cell: like the original game
    ld [wRemnant], a
    push bc
    push de
    push hl
    ld a, 1
    ld [wMode], a
    call LevelPatch
    xor a
    ld [wMode], a
    pop hl
    pop de
    pop bc
IF DEF(TEST_RAM80)
    ld a, $80
ELSE
    ld a, [wRemnant]
ENDC
    ret
Remnant2:
    ldh a, [$FF9B]
    and $F0
    cp $40
    jr nz, .block
    ldh a, [$FF9B]
    sub $10
    ret
.block:
    ld a, [wRemnant]
    ret
    ASSERT @ <= $7F00
SECTION "hook_level", ROM0[$114B]
    call LevelPatch                ; replaces: ld a,[$C0C2] (end of the level loader $10D5)
SECTION "hook_size", ROM0[$0148]
    db $03                         ; 256 KB cartridge (16 banks): banks 8 to 15 are ours
SECTION "dx4", ROMX[$4000], BANK[EXTRA_BANK]
ELSE
SECTION "dx4", ROMX[$65C0], BANK[EXTRA_BANK]
ENDC
; Screen turned back on (screen off): prepares the icon, the gauge and the gradient
DxSetup:
    ld a, $FF
    ld [wGradBuf], a
IF PLUS
    xor a
    ld [wLogoPal], a               ; the scene palettes were just loaded (the title's)
ENDC
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
    jr z, .nojack
    call ArmHud                    ; palette X free in this scenery (Batwing, bell tower, Jack's room): bar armed right away
    call HudWrite
.nojack:
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
REPT GSTEP-1
    ld a, [hl+]
    ld [de], a
    inc de
ENDR
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
IF PLUS
    ld hl, LifeList                 ; do colors live in this scenery? (scene, address of its table)
.ll:
    ld a, [hl+]
    cp $FF
    jr z, .nolife
    ld b, a
    ld a, [wScene]
    cp b
    jr z, .lok
    inc hl
    inc hl
    jr .ll
.lok:
    ld a, [hl+]
    ld [wLifePtr], a
    ld a, [hl]
    ld [wLifePtr+1], a
    xor a                          ; start again from step 0 at each screen-on (the level start text reads well there)
    ld [wLife], a
    ld [wLife+1], a
IF !DEF(NO_LIFE)
    ld a, [wNight]
    or 4                           ; bit 2: signs, lamps, barrels, beacons, flames
    ld [wNight], a
ENDC
.nolife:
ENDC
IF PLUS
    ld a, [wScene]
    cp PARA_A
    jr z, .para
    cp PARA_B
    jr nz, .nopara
.para:
    ldh a, [$FF97]
    ld [wSlow], a
    ld a, [wNight]
    or 8                           ; bit 3: slow scrolling of some bands (Batwing)
    ld [wNight], a
.nopara:
ENDC
    ld a, 1
    ld [wDx], a
    ret

; Night falls: the step depends on the level page ($FF98). At each new step, the colors of the gradient
; steps slide one notch along the ramp (from yellow towards night) and the waves follow. Bank EXTRA_BANK.
PhaseCheck:                        ; called at line 15 when wNight is not zero (bit 1: bar to be armed, bit 0: night)
    ld a, [wNight]
    bit 1, a
    call nz, ArmHud
IF PLUS
    ld a, [wNight]
    bit 2, a
    call nz, Life
    ld a, [wNight]
    bit 3, a
    call nz, Parallax
ENDC
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
IF PLUS
    ld de, wGradBuf+NIGHT_FIRST*GSTEP+GSTEP-4   ; the first color of each nightfall step (from step NIGHT_FIRST on)
ELSE
    ld de, wGradBuf+GSTEP-(GSTEP/3)*2      ; the first color of each step (after the line)
ENDC
    ld b, NIGHT_STEPS
.c:
    ld a, [hl+]
    ld [de], a
    inc de
    ld a, [hl+]
    ld [de], a
REPT GSTEP-1
    inc de
ENDR
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
; The Batman icon and the gauge switch to palette X (5 cells of the bar). Outside line display.
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
IF PLUS
; Living colors: every 8 frames, one step further. Nothing is written to the palettes here: we change the color
; that line 15 will give back (wPalX, color 0) and those of the first line steps (two colors each).
Life:
    ld hl, wLife
    inc [hl]
    ld a, [hl+]
    and 7
    ret nz
    ld a, [hl]
    inc a
    and 63
    ld [hl], a
    ld l, a
    ld h, 0
    add hl, hl
    ld d, h
    ld e, l
    add hl, hl
    add hl, hl
    add hl, hl
    ld a, l
    sub e
    ld l, a
    ld a, h
    sbc d
    ld h, a                        ; step * 14
    ld a, [wLifePtr]
    ld e, a
    ld a, [wLifePtr+1]
    ld d, a
    add hl, de
    ld a, [hl+]
    ld [wPalX], a
    ld a, [hl+]
    ld [wPalX+1], a
    ld de, wGradBuf+GSTEP-4        ; the two colors of each of the first three steps
REPT 3
REPT 4
    ld a, [hl+]
    ld [de], a
    inc de
ENDR
REPT GSTEP-4
    inc de
ENDR
ENDR
    ret
    LifeData
; Slow scrolling (Batwing): a running total of the level scroll ($FF97, signed deltas); line steps aimed at SCX
; ($43) get total >> k (k = their index: 0 = the game's own scroll, 1 = half, 2 = quarter). The scenery of these
; bands repeats every 16 or 32 columns: any column of the screen memory shows the right picture there.
Parallax:
    ldh a, [$FF97]
    ld b, a
    ld hl, wSlow
    sub [hl]
    ld [hl], b
    inc hl
    ld c, a                        ; C = signed delta
    ld e, 0
    bit 7, c
    jr z, .pos
    dec e
.pos:
    ld a, [hl]
    add a, c
    ld [hl+], a
    ld c, a
    ld a, [hl]
    adc a, e
    ld [hl], a
    ld b, a                        ; BC = total
    srl b
    rr c
    ld d, c                        ; D = total >> 1
    srl b
    rr c                           ; C = total >> 2
    ld hl, wGradBuf
.s:
    ld a, [hl+]
    cp $FF
    ret z
    ld a, [hl+]                    ; index = k
    ld b, a
    ld a, [hl+]
    cp $43
    jr nz, .n
    ld a, b
    and a
    jr nz, .k1
    ldh a, [$FF97]
    jr .w
.k1:
    dec a
    ld a, d
    jr z, .w
    ld a, c
.w:
REPT 4
    ld [hl+], a
ENDR
    jr .s
.n:
REPT 4
    inc hl
ENDR
    jr .s
; Reads retouches stored in bank FAR_BANK: this code is copied to wFar (RAM) and runs from there.
FarCode:
    ld a, FAR_BANK
    ldh [hBank], a
    ld [$2000], a
.l:
    ld a, [hl+]
    and a
    jr z, .fin
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
.fin:
    ld a, EXTRA_BANK
    ldh [hBank], a
    ld [$2000], a
    ret
FarCodeEnd:
    ASSERT FarCodeEnd-FarCode <= 40
ENDC
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
IF PLUS
    ld hl, FarCode                 ; the reading routine for bank FAR_BANK, copied to RAM at each screen-on
    ld de, wFar                    ; (the level loader uses it too: added scenery, form 3)
    ld b, FarCodeEnd-FarCode
.cp:
    ld a, [hl+]
    ld [de], a
    inc de
    dec b
    jr nz, .cp
ENDC
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
IF PLUS
    bit 7, h                       ; address + $8000: the retouches are in bank FAR_BANK
    jr z, .l
    res 7, h
    jp wFar
ENDC
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
IF PLUS
SECTION "dx9", ROMX[$4000], BANK[LEVEL_BANK]
; Scenery added to the level just loaded (stage $C0C2): list of (address, tile), 0 0 = end.
; We only write on an EMPTY cell (tile $25) or a scenery one (80-FF): never on a block, an item or a floor.
LevelDo:
    ld a, [wMode]
    and a
    jp nz, Remnant
    ld a, [$C0C2]
    ld b, a
    ld hl, LevelTab
.t:
    ld a, [hl+]
    and a
    ret z
    cp b
    jr z, .ok
    inc hl
    inc hl
    inc hl
    jr .t
.ok:
    ld a, [hl+]                    ; table form: 0 = list (address, tile), 1 = one byte per level cell
    ld c, a
    ld a, [hl+]
    ld h, [hl]
    ld l, a
    ld a, c
    cp 2                           ; form 2: template (size, then N columns x 16 cells), then a list
    jr nz, .form
    call LevelTpl
    jr .l
.form:
    ld a, c
    cp 3                           ; form 3: list of runs (length, address, cells) in bank FAR_BANK, read by wFar
    jp z, wFar
    and a
    jr z, .l
    ld de, $CC00
.dl:
    ld a, [hl+]
    and a
    jr z, .dn
    ld a, [de]
    cp $25
    jr z, .dw
    cp $80
    jr c, .dn
.dw:
    dec hl
    ld a, [hl+]
    ld [de], a
.dn:
    inc de
    ld a, d
    cp $E0
    jr nz, .dl
    ret
.l:
    ld a, [hl+]
    ld e, a
    ld a, [hl+]
    ld d, a
    or e
    ret z
    ld a, [de]
    cp $25
    jr z, .w
    cp $80                         ; or on a piece of scenery (tiles 80-FF: no effect on the game, like empty)
    jr nc, .w
    inc hl
    jr .l
.w:
    ld a, [hl+]
    ld [de], a
    jr .l
; Template in HL (size, then N columns x 16 cells, column by column like the level): copied over the whole level,
; cell by cell, where the level has empty (25) or scenery (80-FF), if the template cell is not 0. HL returned after it.
LevelTpl:
    ld a, [hl+]
    ld [wTplSize], a                  ; size of a block: 16 x number of columns (0 = 256)
    ld de, $CC00
.block:
    push hl
    ld a, [wTplSize]
    ld c, a
.cell:
    ld a, [hl+]
    and a
    jr z, .next
    ld b, a
    ld a, [de]
    cp $25
    jr z, .write
    cp $80
    jr c, .next
.write:
    ld a, b
    ld [de], a
.next:
    inc de
    ld a, d
    cp $E0
    jr z, .fin
    dec c
    jr nz, .cell
    pop hl
    jr .block
.fin:
    pop hl
    ld a, [wTplSize]
    ld c, a
    ld b, 0
    and a
    jr nz, .p
    inc b
.p:
    add hl, bc                     ; HL = just after the template
    ret
; Broken block in HL: the wall tile behind it, from the stage's table (otherwise wRemnant keeps 80).
Remnant:
    ld d, h
    ld e, l
    ld a, [$C0C2]
    ld b, a
    ld hl, RemnantTab
.t:
    ld a, [hl+]
    and a
    ret z
    cp b
    jr z, .ok
    inc hl
    inc hl
    jr .t
.ok:
    ld a, [hl+]
    ld h, [hl]
    ld l, a
.l:
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    ld b, a
    or c
    ret z
    ld a, c
    cp e
    jr nz, .n
    ld a, b
    cp d
    jr nz, .n
    ld a, [hl]
    ld [wRemnant], a
    ret
.n:
    inc hl
    jr .l
RemnantTab:
    RemnantData
LevelTab:
    LevelData
Dx9End:
    ASSERT Dx9End <= $8000
SECTION "dx10", ROMX[$4000], BANK[FAR_BANK]
    FarExtraData
    FarLevelData
Dx10End:
    ASSERT Dx10End <= $8000
ENDC

IF PLUS
; End credits: before THE END, "Thanks for DX version: Enker, Bodom, Rockfordlr".
; The game's reader (bank 6, $6F2D) reads the text at $6FA6 + offset ($C4D9-$C4DA); there is no room there. From
; offset $01ED (the first blank line after SUPER CONBI), it reads the rest here: the added block, then the original end.
; Lines of 10 characters (0-9 = 00-09, A-Z = 0A-23, dash 24, space 25, dot 90), $80 = blank line, $81 = end.
DEF CREDIT_SPLIT EQU $01ED
SECTION "hook_credits", ROMX[$6F2D], BANK[6]
    call CreditAddr                ; replaces: ld de,$6FA6 / adding the offset (17 bytes up to ld a,[de])
REPT 14
    nop
ENDR
SECTION "dxcredits", ROMX[$7F42], BANK[6]
CreditAddr:                        ; DE = address of the next character; HL kept
    ld a, [$C4DA]
    ld d, a
    ld a, [$C4D9]
    ld e, a
    push hl
    ld hl, $6FA6
    ld a, d
    cp HIGH(CREDIT_SPLIT)
    jr c, .ok
    jr nz, .next
    ld a, e
    cp LOW(CREDIT_SPLIT)
    jr c, .ok
.next:
    ld hl, CreditTail - CREDIT_SPLIT
.ok:
    add hl, de
    ld d, h
    ld e, l
    pop hl
    ret
CreditTail:
    db $80,$24,$24,$24,$24,$24,$24,$24,$24,$24,$24,$1D,$11,$0A,$17,$14
    db $1C,$25,$0F,$18,$1B,$0D,$21,$25,$1F,$0E,$1B,$1C,$12,$18,$17,$24
    db $24,$24,$24,$24,$24,$24,$24,$24,$24,$80,$0E,$17,$14,$0E,$1B,$25
    db $25,$25,$25,$25,$0B,$18,$0D,$18,$16,$25,$25,$25,$25,$25,$1B,$18
    db $0C,$14,$0F,$18,$1B,$0D,$15,$1B,$80,$80,$80,$80,$80,$80,$80,$80
    db $80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$80,$25,$1D,$11
    db $0E,$25,$0E,$17,$0D,$25,$25,$80,$80,$80,$19,$1B,$0E,$1C,$0E,$17
    db $1D,$0E,$0D,$25,$25,$25,$25,$25,$0B,$22,$25,$25,$25,$25,$80,$EC
    db $EE,$F0,$F2,$F4,$F6,$F8,$FA,$FC,$FE,$ED,$EF,$F1,$F3,$F5,$F7,$F9
    db $FB,$FD,$FF,$80,$81
CreditEnd:
    ASSERT CreditEnd <= $8000
ENDC

IF PLUS
IF SHINE
; Title screen (Plus edition). B = 1: logo loop; B = 0: title screen loop.
; Spinning logo in "metallic gold": each row of logo cells has its own palette (attr_plus,
; in the workshop). During the logo, palettes 1 and 3 to 7 (signature, letters, stars of the title, not shown yet)
; receive golds, light at the top to amber at the bottom, with a rebound of light at the bottom; for the title they get their
; colors back. Done during vertical blank, interrupts off (the game changes SCY on every line of the logo).
SECTION "dxtitle", ROMX[$7D30], BANK[EXTRA_BANK]
TitleWork:
    ld a, b
    cp 2
    jp z, CutVie                   ; B = 2: every frame (vertical blank interrupt), Batcave screens
    ld a, [wIsCGB]
    and a
    ret z
    ld a, [wScene]
    dec a
    ret nz                         ; scene 1 = logo and title
    ld a, b
    and a
    jr nz, .logo0                  ; logo loop
    ld a, [wFade]
    dec a
    cp 63
    ret c                          ; fade running: the palettes belong to it
    ldh a, [$FF42]
    and a
    jr z, .fade                   ; title loop, logo frame (logo / title crossfade: every other frame): the golds
    ld a, [wLogoPal]               ; title frame: its colors
    and a
    jp z, .shine
    ldh a, [rLY]
    sub 144
    cp 7
    ret nc                         ; not at the start of vertical blank: next frame
    di
    ld hl, wLogoSave
    ld c, $80 + 1*8 + 2
    call .write
    ld c, $80 + 3*8 + 2
    ld b, 5
.lr:
    push bc
    call .write
    pop bc
    ld a, c
    add a, 8
    ld c, a
    dec b
    jr nz, .lr
    ei
    xor a
    ld [wLogoPal], a
    jp .shine
.fade:
    ld a, [wLogoPal]
    and a
    ret nz
    ldh a, [rLY]
    sub 144
    cp 7
    ret nc
    jr .gold
.logo0:
    xor a
    ld [wFade], a                  ; the fade starts over with every logo
.logo:
    ld a, [wLogoPal]               ; logo loop: load the golds once, at the start of a vertical blank
    and a
    ret nz
    call .vbl
.gold:
    di
    ld hl, LogoGold
    ld de, wLogoSave
    ld c, $80 + 1*8 + 2            ; palette 1, color 1
    call .pal
    ld c, $80 + 3*8 + 2
    ld b, 5                        ; palettes 3 to 7
.lg:
    push bc
    call .pal
    pop bc
    ld a, c
    add a, 8
    ld c, a
    dec b
    jr nz, .lg
    ei
    ld a, 1
    ld [wLogoPal], a
    ret
.vbl:                              ; wait for the start of vertical blank (once per palette change)
    ldh a, [rLY]
    cp 144
    jr nz, .vbl
    ret
.pal:                              ; C = index (color 1): saves the 6 bytes at DE, writes 6 bytes from HL
    push bc
    ld b, 6
.pg:
    ld a, c
    and $3F
    ldh [rBCPS], a                 ; reading: no auto-increment
    ldh a, [rBCPD]
    ld [de], a
    inc de
    inc c
    dec b
    jr nz, .pg
    pop bc
.write:                             ; C = index (color 1): writes 6 bytes from HL
    ld a, c
    ldh [rBCPS], a
REPT 6
    ld a, [hl+]
    ldh [rBCPD], a
ENDR
    ret
.shine:
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
    ld hl, TitleEclatTab
    add hl, bc
    ld c, $80 + 2*8 + 6
    ld b, 5
.l:
    ldh a, [$FF41]
    and $02
    jr nz, .l                      ; wait for an HBlank or VBlank (palettes accessible)
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
    ret
TitleEclatTab:
    ShineData
LogoGold:                          ; palettes 1, 3, 4, 5, 6, 7: colors 1 (emblem black), 2 (outline), 3 (gold)
    db $43,$00,$D6,$05,$7F,$23,$43,$00,$D5,$09,$DF,$53
    db $43,$00,$51,$01,$BC,$0E,$43,$00,$0F,$01,$19,$06
    db $43,$00,$EE,$00,$75,$01,$43,$00,$73,$05,$5B,$0E
DxTitleEnd:
    ASSERT DxTitleEnd <= $8000
ENDC
ENDC

IF PLUS
; Batcave (still screens 10 and 12: the police at the start, the Joker on screen): the lights live.
; Every frame, at the start of vertical blank
; (interrupt, outside levels only: $0CF6): every 4 frames, one step out of 32. Palette 5: amber and red
; dots blinking at their own pace. (Green screens and cyan gauges were tried and left still.)
; All 4 colors of the palette are rewritten.
DEF wCutCnt EQU $C5B0
DEF wStarN EQU $C5B2                ; credits: frames since the statue settled (stars appearing)
DEF wSprN EQU $C5B3                 ; credits: sprite stars already shown
SECTION "hook_vbl", ROM0[$0CF6]
    call VblDx                     ; replaces: call $1818 (only done outside levels: $FF9A = 0)
SECTION "dxvbl", ROM0[$0000]       ; (rst $00 vector, never called: $FF in the game)
VblDx:
    call $1818
    ld b, 2
    jp TitleCommon                 ; bank EXTRA_BANK, TitleWork with B = 2 (returns HL = $CB00: no effect here)
; Logo -> title fade. The original game goes from the logo to the title by alternating frames of each ($C1A5 = 0
; during that time, SCY 0 / $7C): a fade on the Game Boy's slow LCD, a flicker on a modern screen. Here, during that
; time, the frame shown no longer depends on the game: the logo fades out (32 frames), then the title fades in (32
; frames) and stays. Precomputed palettes (FadeData, tools/gen_tables.py): the 8 background palettes, written every
; 4 frames during vertical blank.
; Start pressed during the fade: the full title at once. Nothing changes in how the game runs.
SECTION "dxfade", ROMX[$7600], BANK[EXTRA_BANK]
TitleFade:
    ld a, [$C1A5]
    and a
    jr z, .trans                   ; logo -> title transition running
    inc a
    ret nz                         ; before the transition: nothing
    ld a, [wFade]                  ; transition over or cut by Start
    dec a
    cp 63
    ret nc
    ld a, 15                       ; fade cut: the full title
    call .write
    ld a, 64
    ld [wFade], a
    ret
.trans:
    ld a, [wFade]
    cp 64
    jr nc, .title                  ; fade done: the title stays
    inc a
    ld [wFade], a
    dec a
    ld c, a
    and 3
    jr nz, .scy
    ld a, c
    rrca
    rrca
    and $0F                        ; step 0-15
    call .write
.scy:
    ld a, [wFade]
    cp 33
    jr nc, .title
    xor a                          ; frames 1-32: the logo
    ldh [$FF42], a
    ret
.title:
    ld a, $7C
    ldh [$FF42], a
    ret
.write:                            ; A = step: the 8 background palettes (64 bytes)
    ld l, a
    ld h, 0
REPT 6
    add hl, hl
ENDR
    ld de, FadeTab
    add hl, de
    ld a, $80
    ldh [rBCPS], a
    ld c, LOW(rBCPD)
    ld b, 8
.l:
REPT 8
    ld a, [hl+]
    ldh [c], a
ENDR
    dec b
    jr nz, .l
    xor a
    ld [wLogoPal], a               ; no golds to put back: the title then gets its shine again
    ret
FadeTab:
    FadeData
DxFadeEnd:
    ASSERT DxFadeEnd <= $7B00
SECTION "dxcutscene", ROMX[$7B00], BANK[EXTRA_BANK]
CutVie:
    ld a, [wIsCGB]
    and a
    ret z
    ld a, [wScene]
    cp 10
    jr z, .bat
    cp 12
    jr z, .bat
    cp 15
    jr z, .gen
    dec a
    ret nz
    jp TitleFade                   ; scene 1: logo -> title fade
.gen:
    ldh a, [$FF4A]
    and a
    jr z, .settled
    xor a                          ; the statue is still rising (window not in place): plain sky, no stars
    ld [wStarN], a
    ld [wSprN], a
    ret
.settled:                            ; one more star
    ld a, [wStarN]                 ; every 8 frames, 22 in all (AppearTab)
    cp 22*8
    jr nc, .all
    inc a
    ld [wStarN], a
    dec a
    ld c, a
    and 7
    jr nz, .all
    ld a, c
    rrca
    and $7C                        ; (frames / 8) x 4 bytes
    ld l, a
    ld h, 0
    ld de, AppearTab
    add hl, de
    ld a, [hl+]
    cp $FF
    jr nz, .window
    ld a, [wSprN]                  ; one more sprite star
    inc a
    ld [wSprN], a
    jr .all
.window:
    ld e, a                        ; a window cell (around the statue) gets its star
    ld a, [hl+]
    ld d, a
    ldh a, [$FF4F]
    push af
    xor a
    ldh [$FF4F], a
    ld a, [hl]
    ld [de], a
    pop af
    ldh [$FF4F], a
.all:
    call CutStars                  ; fixed stars under the text (sprites behind the background)
    ld hl, CutDescG                ; the credits (scene 15), twinkling stars (palettes 5 and 6)
    ld b, 2
    jr .ok
.bat:
    ld hl, CutDesc
    ld b, 1                        ; only palette 5 lives (red and amber dots);
                                   ; green screens and gauges stay still
.ok:
    push hl
    push bc
    ld hl, wCutCnt
    inc [hl]
    ld a, [hl]
    and 3
    jr z, .step
    pop bc
    pop hl
    ret
.step:
    ld a, [hl]
    rrca
    rrca
    and 31
    ld e, a                        ; E = step (0-31)
    pop bc
    pop hl
.p:
    ld a, [hl+]
    ldh [rBCPS], a                 ; palette, color 0, auto-increment
    ld a, [hl+]
    ld c, a
    ld a, [hl+]
    push hl
    ld h, a
    ld l, c                        ; HL = step table of this palette
    ld d, 0
    add hl, de
    ld a, [hl]                     ; state
    pop hl
    push hl
    ld c, a
    add a, a
    add a, a
    add a, a                       ; x8 bytes per state
    ld c, a
    ld a, [hl+]
    ld h, [hl]
    add a, c
    ld l, a
    jr nc, .nc
    inc h
.nc:
    ld c, 8
.w:
    ld a, [hl+]
    ldh [rBCPD], a
    dec c
    jr nz, .w
    pop hl
    inc hl
    inc hl
    dec b
    jr nz, .p
    ret
CutDesc:                           ; palette index, step table, states
    db $80 + 5*8
    dw CutP5, CutS5
CutP5:
    db $00,$00,$01,$03,$02,$02,$01,$01,$00,$02,$03,$03,$00,$00,$01,$03
    db $02,$02,$01,$01,$00,$02,$03,$03,$00,$00,$01,$00,$02,$02,$01,$01
CutS5:
    db $5F,$2B,$1F,$19,$6A,$0C,$00,$00,$0B,$0D,$1F,$19,$6A,$0C,$00,$00
    db $5F,$2B,$6B,$0C,$6A,$0C,$00,$00,$0B,$0D,$6B,$0C,$6A,$0C,$00,$00
; Credits: 8 fixed stars as sprites behind the background
; (attribute $80, palette 0 = the moon's): the text scrolls in front. Placed in the slots left empty after the
; OAM copy ($FE00, vertical blank). Twinkle: in turn, a star takes the faint drawing (72).
CutStars:
    ld a, [wCutCnt]
    rrca
    rrca
    rrca
    and 7
    ld e, a                        ; E = moment (0-7)
    ld hl, $FE00
    ld a, [wSprN]
    and a
    ret z
    ld d, a                        ; only the stars already shown
    ld bc, StarTab
.lp:
    ld a, [hl]
    and a
    jr nz, .skip
    ld a, [bc]
    inc bc
    ld [hl+], a                    ; y
    ld a, [bc]
    inc bc
    ld [hl+], a                    ; x
    ld a, [bc]
    inc bc
    push af
    ld a, [bc]
    inc bc
    add a, e
    and 7
    jr nz, .bright
    pop af
    ld a, $72                      ; its turn: the faint drawing
    jr .t
.bright:
    pop af
.t:
    ld [hl+], a
    ld a, $80
    ld [hl+], a                    ; behind the background, palette 0
    dec d
    ret z
    jr .end
.skip:
    inc l
    inc l
    inc l
    inc l
.end:
    ld a, l
    cp $A0
    jr c, .lp
    ret
StarTab:                           ; y, x (OAM coordinates), drawing, twinkle offset
                                   ; (12 stars over the left part, around the signal; the game uses 28 slots)
    db 22, 12, $70, 0
    db 26, 78, $71, 3
    db 46, 94, $70, 6
    db 56, 16, $71, 1
    db 68, 82, $70, 4
    db 78, 38, $71, 7
    db 90, 96, $70, 2
    db 102, 20, $71, 5
    db 108, 60, $70, 0
    db 120, 88, $71, 3
    db 132, 28, $70, 6
    db 144, 72, $71, 1
AppearTab:                          ; order of appearance (4 bytes): $FF = one more sprite star;
                                   ; otherwise a window cell address and its drawing (credits stars)
    db $FF, 0, 0, 0
    db $21, $9C, $F0, 0
    db $FF, 0, 0, 0
    db $05, $9C, $F1, 0
    db $FF, 0, 0, 0
    db $66, $9C, $F0, 0
    db $FF, 0, 0, 0
    db $A0, $9C, $F1, 0
    db $FF, 0, 0, 0
    db $E7, $9C, $F0, 0
    db $FF, 0, 0, 0
    db $66, $9D, $F1, 0
    db $FF, 0, 0, 0
    db $80, $9D, $F0, 0
    db $FF, 0, 0, 0
    db $C7, $9D, $F1, 0
    db $FF, 0, 0, 0
    db $23, $9C, $F0, 0
    db $FF, 0, 0, 0
    db $20, $9D, $F1, 0
    db $FF, 0, 0, 0
    db $FF, 0, 0, 0
CutDescG:                          ; credits: stars (palette 5 and palette 6, two paces)
    db $80 + 5*8
    dw CutGA, CutGS
    db $80 + 6*8
    dw CutGB, CutGS
CutGA:
    db $00,$00,$00,$01,$01,$00,$00,$02,$00,$00,$01,$03,$03,$01,$00,$00
    db $00,$01,$01,$00,$00,$00,$02,$00,$01,$01,$00,$00,$03,$01,$00,$00
CutGB:
    db $01,$03,$03,$01,$00,$00,$00,$01,$01,$00,$00,$02,$00,$00,$00,$01
    db $01,$00,$00,$02,$00,$00,$01,$03,$01,$00,$00,$00,$01,$01,$00,$02
CutGS:                             ; 0 sky, 1 star core, 2 arms; 4 states: bright, veiled, flash, off
    db $21,$18,$DF,$5B,$32,$3A,$21,$18,$21,$18,$B6,$42,$4A,$31,$21,$18
    db $21,$18,$FF,$7F,$D8,$42,$21,$18,$21,$18,$8C,$31,$A5,$24,$21,$18
CutEnd:
    ASSERT CutEnd <= $8000
    ; (section placed lower: the museum extras moved to bank 10)
ENDC
