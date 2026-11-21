# Batman DX — Gotham, finally in color

Sunsoft's Game Boy **Batman** (1990), fully colorized for Game Boy Color. One patch, six moods, and an online lab to make your own.

<p align="center"><img src="images/title.gif" alt="The animated title screen" width="480"></p>

The original game uses four shades of grey. Batman DX gives it color without touching a single game rule: same levels, same enemies, same difficulty, same speed. The cartridge still runs on a monochrome Game Boy, where it behaves like the original.

> This repository does **not** contain the game. It contains a patch that you apply to your own copy.

## The easy way: the online lab

**[Open the Batman DX lab](https://guillain-rdcde.github.io/Batman-DX/)**

1. Drop your original ROM into the page.
2. Pick a mood.
3. Download the game in color, or play it right there.

Nothing is uploaded: everything happens in your browser.

<p align="center"><img src="images/lab.png" alt="The lab"></p>

### The editor

The lab is also an editor. It reads the levels and drawings straight from your ROM and shows each place with its real colors. From there you can:

- **change any color** of any place, background or characters;
- **tap a piece of scenery to give it another palette**;
- **give an object transparent edges**: the page shows the drawing enlarged, finds the background dots, and you correct them with a tap.

Then try the result in the page, download your own game or patch, and export your settings to share them.

<p align="center"><img src="images/editor.png" alt="The editor"></p>

## With an IPS patch

1. You need the ROM **Batman - The Video Game (World).gb**: 131,072 bytes, SHA-1 `ef7d6684a0f737c01a1f2cc2c6609e0f3ac1310e`.
2. Take a patch from [`patches/`](patches/): `Batman-DX.ips` is the published edition, the others are the moods.
3. Apply it with any IPS tool (Lunar IPS, Floating IPS, or an online patcher).
4. Give the result a `.gbc` extension and run it in a Game Boy Color emulator.

If the game shows up in black and white, your emulator started it in Game Boy mode: force Game Boy Color mode.

## Before, after

Original on the left, Batman DX on the right, at the same moment of the game.

**The logo**

<p align="center"><img src="images/before-after-01-logo.png" alt="The logo"></p>

**Title screen**

<p align="center"><img src="images/before-after-02-title.png" alt="Title screen"></p>

**Scene: the police**

<p align="center"><img src="images/before-after-03-scene-police.png" alt="Scene: the police"></p>

**Gotham City (1-1, 2-1)**

<p align="center"><img src="images/before-after-04-gotham.png" alt="Gotham City (1-1, 2-1)"></p>

**Chemical plant (1-2, 1-3)**

<p align="center"><img src="images/before-after-05-chemical-plant.png" alt="Chemical plant (1-2, 1-3)"></p>

**Batman vs Jack (1-B)**

<p align="center"><img src="images/before-after-06-jack.png" alt="Batman vs Jack (1-B)"></p>

**Scene: the Joker**

<p align="center"><img src="images/before-after-07-scene-joker.png" alt="Scene: the Joker"></p>

**Flugelheim Museum (2-2, 2-3)**

<p align="center"><img src="images/before-after-08-museum.png" alt="Flugelheim Museum (2-2, 2-3)"></p>

**Scene: the Batmobile**

<p align="center"><img src="images/before-after-09-scene-batmobile.png" alt="Scene: the Batmobile"></p>

**Batwing, sunset (3-1)**

<p align="center"><img src="images/before-after-10-batwing.png" alt="Batwing, sunset (3-1)"></p>

**Batwing, night (3-2)**

<p align="center"><img src="images/before-after-11-batwing-night.png" alt="Batwing, night (3-2)"></p>

**Scene: the Joker on screen**

<p align="center"><img src="images/before-after-12-scene-joker-on-screen.png" alt="Scene: the Joker on screen"></p>

**Cathedral (4-1, 4-2)**

<p align="center"><img src="images/before-after-13-cathedral.png" alt="Cathedral (4-1, 4-2)"></p>

**Batman vs the Joker (4-B)**

<p align="center"><img src="images/before-after-14-bell-tower.png" alt="Batman vs the Joker (4-B)"></p>

**Scene: the ending**

<p align="center"><img src="images/before-after-15-scene-ending.png" alt="Scene: the ending"></p>

**End credits**

<p align="center"><img src="images/before-after-16-credits.png" alt="End credits"></p>

**Game Over**

<p align="center"><img src="images/before-after-17-game-over.png" alt="Game Over"></p>

## Six moods

`Batman-DX.ips` is the published edition: a mix chosen place by place. The five others apply a single mood to the whole game.

<p align="center"><img src="images/moods.png" alt="The six moods"></p>

| Patch | Mood |
|---|---|
| `Batman-DX.ips` | The published edition |
| `Batman-DX-movie.ips` | 1989 movie: the starting colors |
| `Batman-DX-comic.ips` | Comic book: bold colors |
| `Batman-DX-pastel.ips` | Pastel: everything softened |
| `Batman-DX-night.ips` | Gotham by night: dark backgrounds |
| `Batman-DX-green.ips` | Game Boy green: the four original greens |

## The details that matter

<p align="center"><img src="images/details.png" alt="Details"></p>

- **Objects have transparent edges.** Barrels, pipes, blocks and pickups sit on the scenery with no colored square around them. To get there, about a hundred small drawings of the game are retouched at display time, on color hardware only.
- **Gotham's windows are lit**, and the distant towers are drawn as outlines on the sky so they recede.
- **The title screen shines**: a highlight sweeps down the letters once a second.
- **The status bar** keeps its colors (black and yellow) in every level.
- **Enemies are solid.** The cloud enemies of stage 3-2 were hollow in the original drawing, which did not show on a white sky; they are filled in so the city no longer shows through.
- **Bosses flash** when hit, as in the original.

A whole level, for scale:

<p align="center"><img src="images/level-1-1-full.png" alt="Level 1-1 in full"></p>

## What has been verified

- **The game is the same.** The original and Batman DX receive exactly the same inputs and their memory is compared at every frame. On the twelve playable stages, in color and in monochrome, it is identical on every in-game frame compared.
- **The pace holds.** The work added at the end of each frame always finishes before the limit. Screen changes last two to three frames longer, 0.1 to 0.2 % over a playthrough.
- **The patches are reproducible.** Rebuilding from source gives the six ROMs byte for byte.
- **The online lab is tested end to end**: it produces exactly the same six ROMs, and a game edited in the page is run in an emulator to check that the retouch is really there.

What has **not** been verified: the game on real hardware, and a full playthrough by a human. Every place was reached by jumping straight to it. Details are in the [technical notes](TECHNICAL.md#verification).

## Checksums of the produced games

```
2666c2514a39fedb6912cfab656debc7eda92561  Batman-DX.gbc (published edition)
b4693564ef1f7dbad8819d8911e533a9929326d3  Batman-DX-movie.gbc
34d27c6a76a9dc8596b1f301adb69c92726d8481  Batman-DX-comic.gbc
e5b16dcb0e188d03ad91d5ca1e2201a8494142c9  Batman-DX-pastel.gbc
cb148e1b984903578a066a166597204c2fa5fdd3  Batman-DX-night.gbc
78ba7d9ca8b4180b314f0568bba53e084e41243c  Batman-DX-green.gbc
```

## Building from source

You need [RGBDS](https://rgbds.gbdev.io) and Python 3.

```sh
./build.sh "Batman - The Video Game (World).gb"         # the published edition
./build.sh "Batman - The Video Game (World).gb" night   # one mood
```

The result lands in `out/`. The script refuses to build if the added code overwrites anything but free cartridge space.

## Share your colors

In the lab, “Export my settings” produces a small `.json` file with your colors, palette choices and retouches. Open an issue on this repository with the file and a screenshot: the best ones will join the moods.

## The rules of the hardware

A Game Boy Color does not paint pixels freely. Everything in Batman DX works inside five rules:

- **The screen is a grid of 8×8 cells, and each cell gets one palette of 4 colors.** You cannot give two palettes to one cell.
- **Only 8 background palettes exist at a time**, plus 8 for characters. Gotham uses all eight.
- **A drawing is made of 4 shades, not colors.** The palette decides what each shade looks like. The same drawing can be recolored, but two parts drawn in the same shade always share a color.
- **The background has no transparency.** Only characters do. A barrel is background.
- **The same small drawing is reused everywhere.** Recolor one brick and every identical brick of the level follows.

So why did barrels first show a colored square around them? In the original drawing, the lightest shade is used twice: for the highlight on the barrel and for the empty corners around it. One shade, one color: a bright highlight meant bright corners. The fix is to redraw the barrel so the corners keep the lightest shade, now set to the sky color, while the highlight moves to the next shade. The barrel loses one nuance and its corners melt into the sky. That is what “transparent” means here, and it only works where the scenery behind is a single flat color.

The [technical notes](TECHNICAL.md) explain the game, the patch and the verification, address by address.

## Credits

Batman DX is a non-commercial fan work, not affiliated with Sunsoft, Nintendo, DC or Warner Bros. *Batman* and its characters are trademarks of DC. The code in this repository is MIT licensed, except the lab page (`docs/`), under GPL-3.0 because it embeds the WasmBoy emulator; it contains no part of the original game beyond what the patch necessarily has to modify.

By Guillain d'Erceville. Signed “DX EcstazY 2026” on the title screen.
