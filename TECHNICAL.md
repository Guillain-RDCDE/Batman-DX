# Batman DX — technical notes

This page explains how the original game works, what the patch adds, and how everything was verified. Addresses are hexadecimal, written `bank:address`.

## The original game

| | |
|---|---|
| Cartridge | MBC1, 128 KB, 8 banks of 16 KB, no save memory |
| Expected ROM | `Batman - The Video Game (World).gb`, SHA-1 `ef7d6684a0f737c01a1f2cc2c6609e0f3ac1310e` |
| Free space | about 1,200 bytes in bank 0, 7,000 in bank 6, 2,500 at the end of bank 6 |

Four facts make a clean colorization possible.

**1. The game never changes its palettes.** It writes `BGP = E4`, `OBP0 = E4`, `OBP1 = 1B` once and for all. There is no fade to follow. `OBP1` (the inverted palette) is only used to flash a boss when hit.

**2. All scenery goes through a single path while the screen is on.** The game queues its writes in a list (`CB01` = length, `CB02`… = commands) that the end-of-frame routine runs through `0EF3` then `0EF9`. A command is an address (2 bytes), a type and count (1 byte), and data. Four types: row, filled row, column, filled column. Scrolling is one column of 16 cells, built at `3A49`.

**3. While the screen is off, the game draws directly**, then turns the screen back on at six precise places: `0212` (title), `04D0` and `054B` (text screens), `0706` (level), `0AA7` (Game Over), `6:6885` (cutscenes).

**4. Characters are described by a table.** Routine `100E` reads the table of 119 poses at `1:512A`. Each piece takes 4 bytes: vertical offset, horizontal offset, tile number, attribute. The three low bits of the attribute do nothing on a Game Boy.

Other useful landmarks:

- The current level is unpacked in memory from `CC00` to `DFFF`: 20 pages of 16×16 cells, stored by columns. Loaded by `10D5` (data in bank 7).
- Graphics sheets are loaded by `0F74` (banks 3 and 4, numbers `00` to `1E`) and `0FC1` (banks 5 to 7).
- The current stage is at `C0C2` (1 to 13). A new game writes 1 there at `0475`.
- Blocks: tiles `40` to `4F` = block hiding an item, `50` = plain block. Released items are tiles `30` to `37`.
- The sound engine runs on the timer (`0050` → `2FF8`), independently of frames.
- After the final fight, the game chains the ending scene and then end credits at `0B3A`.

## What the patch does

The patch adds about 1,000 bytes of code in bank 0 (from `3B55`) and the color data in bank 6 (`4CD9` and `7636`). It moves nothing: it replaces a few instructions with calls.

The published edition adds about 370 more bytes in bank 0 (the end of the same area, plus the empty `rst` vectors `000B`–`003F` and the free bytes `0061`–`00EB`), and 6,400 bytes of code and data in the free end of bank 4 (from `65C0`). The five other moods do not include any of it.

### Knowing whether the console has color

At power-on, a color console puts `11` in register A. The patch records it (`C520`). On a monochrome Game Boy, all added code is skipped and the game behaves like the original.

### Scenes

The game is split into 16 scenes: text screens, title, the eight level sceneries, five cutscenes, the credits. The current scene (`C521`) is deduced from the graphics sheet the game has just loaded.

Each scene carries in ROM:

- a 256-byte table “tile number → palette number”;
- 8 background palettes and 8 character palettes, 4 colors each;
- the palette forced on the two top rows (the status bar), or none;
- a list of retouches: bytes to write into video memory.

### When the screen turns back on

The six instructions that turn the screen on are replaced by a call (`rst $08`, or `rst $10` for text screens). With the screen still off, the patch:

1. copies the scene table into memory (`C600`);
2. loads the 16 palettes;
3. applies the retouches;
4. gives each of the 2,048 cells of both screen maps its palette.

### During play

Routine `0EF9` is hooked. After each scenery command, the patch writes the palettes of the same cells by reading the table. The scrolling column has a direct, unrolled path that lays down the 16 tiles then the 16 palettes barely slower than the original laid down the tiles alone. The status bar and the window are left alone: their palettes never change.

### Line effects (published edition)

In a level, the game already takes an interrupt at line 15 to keep the status bar still while the scenery scrolls. Its handler (`0E0D`) has one branch per screen mode. Only two branches are hooked, `0E18` (normal level) and `0E1E` (Jack's room): the branch that draws level openings and title cards line by line is not touched, so those effects keep their exact timing.

From that line 15, the patch chains its own line interrupts by moving the compare line (`LYC`), and gives it back to the game at the end of the picture:

1. **Line 15.** One palette, called palette X, is shared by the Batman icon, the energy gauge and a piece of scenery. It gets its scenery colors back.
2. **Sky gradient.** On stage 3-1, eleven steps down the screen each rewrite the sky color during a horizontal blank. Stage 3-2 does the same with four steps.
3. **Line 143.** Palette X takes the colors of the bar again, the gauge color being chosen from the energy (`C0C8`). This must be over before line 145, which the game polls to turn the screen off (`0EB8`).

The game rewrites `LYC` to 15 after each frame's work (`07F8`); that instruction is hooked so it leaves the chain alone while it runs. If an interrupt comes late, the passed steps are skipped and the bar is still written.

A step costs about 90 machine cycles, most of it waiting for the horizontal blank. Eleven steps keep stage 3-1 at full speed; twenty-two made it 6 to 13 % slower.

**Nightfall.** On stage 3-1 the eleven sky colors are a window on a ramp of 22 colors, from night to the yellow of the horizon. Every two pages of scenery (`FF98`), the window slides one notch towards the night; the wave band and the city windows, two groups of buildings on two colors of the same palette, follow. That routine lives in bank 4 and is called from line 15 through a short relay.

### Extra retouches (published edition)

The scene areas of bank 6 are nearly full, so the published edition keeps a second list of retouches per scene in bank 4, in the same format, applied right after the first one: lit windows, glass panes, filled enemies, and the title screen. The title logo and the emblem were two dots off center: their tiles are redrawn shifted, 168 in all, and the cells that needed a new tile get their palette from an entry that selects the attribute map.

### Characters

At build time, a tool writes the palette number into the three free bits of each piece's attribute, according to the tile number: Batman, shots and items, three families of enemies. The game copies those bits without knowing. When a boss flashes, the patch turns the “inverted palette” flag into “palette 7 − p”, at no extra cost.

### Retouched drawings

A background cell has a single palette, and its lightest shade is both the highlight on the object and the background around it. To give a barrel, a pipe or a block transparent edges, its tiles are redrawn at display time: the background keeps shade 0, which takes the scenery color, and the highlight moves to shade 1. About a hundred tiles are affected, all scenes combined. The title screen signature is added the same way. These retouches only happen on color hardware.

### The title screen shine

The title letters span five rows, each with its own palette. In the two title screen loops (`0214` and `02C6`), the patch rewrites one color per palette every four frames, waiting for a moment when palettes are accessible. Nothing is added during play.

### Memory used

`C520` to `C5FF` and `C600` to `C6FF`. The original game never writes to those areas on any stage tried.

## The editor in the lab

The lab page rebuilds, in the browser, what the game does at load time. It unpacks the graphics sheets (the routines at `0F74` and `0FC1`) and the levels (`10D5`) from the original ROM, then reads the 16 scenes from the patched ROM into an editable model: table, palettes, retouches. Every change goes into the model; the game is produced by writing the model back into the two areas reserved for scene data in bank 6 (`4D67`–`67FF` and `7636`–`7FFF`) and fixing the checksum. With no change, this gives back the built ROM byte for byte.

A retouch is one more entry in a scene's list: 16 bytes to write over a tile when the screen turns back on. The published edition leaves room for about 50 more.

The page does not read bank 4 nor the line effects: its previews show a place without the gradient, the nightfall and the extra retouches of the published edition. Those bytes are left as they are, so the game it produces keeps them.

## The colors

The six moods are described in `src/moods/*.json`: tables, palettes and retouches for each scene. The build only needs those files. They can be edited with the online lab, which exports the same information.

## Verification

### The game is the same

`tools/compare.py` runs the original in monochrome and Batman DX side by side. Both receive exactly the same inputs, injected into the joypad reading routine. At every game frame it compares the game memory and, every eight frames, the level and the screen.

Result on the published version, 8,000 to 12,000 game frames per run:

| Run | In-game result |
|---|---|
| Stages 1, 2, 3, 6 to 12, Batman DX in color | identical on every frame compared |
| Stages 4 and 5, Batman DX in color | 1 and 3 frames out of about 5,000 differ, in the displayed characters only |
| Stages 1, 4, 6, 8, 9, 11, Batman DX in monochrome | identical on every frame compared |

On those few frames the original shows the same characters twice in its table: the picture was sampled one frame apart in the two games, because the color game sometimes takes one frame more. The game memory is identical before and after.

Three honest caveats:

- **Cutscenes are not compared frame by frame.** Their text advances with the sound, which runs on a clock independent of frames. The original compared with itself with that clock shifted drifts in the same way. The comparison therefore restarts from zero at each level load.
- **The order of characters in the table is not compared**, only the characters displayed. The game fills that table from the start on one frame and from the end on the next; the direction depends on how many frames have elapsed since power-on.
- **Excluded from the comparison**: the sound engine, the stack, the already consumed screen buffer, and the patch's own variables.

### The pace

End-of-frame work must finish before line 153. Across the runs above, the original stops at line 151 at the latest and Batman DX at line 152. The rare frames where the original already overruns overrun in the same way. Screen changes last two to three frames longer.

The line effects take their time from the game, not from the end of the frame. Twelve long automatic playthroughs, one per stage, were run on the previous edition and on this one with the same inputs, timed on real frames: the game never stalls, and 0.1 % fewer game frames are run (0.5 % on two stages). On eleven stages the same number of levels is loaded and the screen is turned off as many times; on the twelfth the two runs drift apart after a while, as such a small shift is enough to change the outcome of a fight.

### The game's own line effects

The opening of a level is drawn line by line by the original game. Its pictures are compared in monochrome between the original and Batman DX on three stages: 195 distinct pictures on each side, all found in the original but one to three, exactly as with the previous edition.

### Two emulators

Comparisons run on PyBoy. The game was also run on cycle-accurate Gambatte, in color and in monochrome: logo, title, cutscene and first level display without defects, and so do the sky gradient, the nightfall and the status bar of the published edition. The lab page uses a third emulator, WasmBoy.

### Build and online lab

- Rebuilding from source gives the six ROMs byte for byte.
- Each patch, applied to the original ROM, gives the matching ROM.
- `tools/test_page.py` drives the page in a browser: wrong file rejected, six moods identical to the build, downloaded patch identical to the repository's, changing one color only alters its two bytes and the checksum, export then import give the same game.
- `tools/test_editor.py` checks the editor: the page reads the eleven levels exactly as a separate reference reader does, and the museum drawings exactly as the original game puts them in video memory; a tile retouched with real clicks ends up in the produced ROM, in the right scene only; that ROM is then run in an emulator, where the retouched tile is found in video memory and its new palette in the table; removing the retouch gives back the starting game byte for byte; when the cartridge is full the page refuses cleanly and the game still boots.

### What is not verified

- The game on real hardware or a flash cartridge.
- A full playthrough by a human. Each place was reached by forcing the stage number, the credits by forcing the jump to `0B3A`.
- Items released by blocks were seen by placing them by hand in the scenery, not by breaking a block.

## Rebuilding

```sh
./build.sh "Batman - The Video Game (World).gb" [dx|movie|comic|pastel|night|green]
```

The script checks the ROM checksum, generates the tables, assembles `src/dx.asm` over the ROM, writes the character palettes, fixes the header and writes the ROM and the patch into `out/`. It refuses to build if the added code overwrites anything but `FF` bytes of the original cartridge.
