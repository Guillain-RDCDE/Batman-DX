#!/bin/sh
# Builds Batman DX from YOUR original ROM (not provided).
#   ./build.sh "path/to/Batman - The Video Game (World).gb" [mood]
# moods: dx (default, the published edition), movie, comic, pastel, night, green
# Needs: rgbds (rgbasm, rgblink, rgbfix) and python3. Output: out/Batman-DX-<mood>.gbc and .ips
set -e
cd "$(dirname "$0")"
ROM="$1"; V="${2:-dx}"
[ -f "$ROM" ] || { echo "usage: ./build.sh original_rom.gb [mood]"; exit 1; }
SHA=$( (shasum "$ROM" 2>/dev/null || sha1sum "$ROM") | cut -c1-40)
[ "$SHA" = "ef7d6684a0f737c01a1f2cc2c6609e0f3ac1310e" ] || { echo "This is not the expected ROM (SHA-1 $SHA)."; exit 1; }
mkdir -p build out
cp "$ROM" build/base.gb
python3 tools/gen_tables.py "src/moods/$V.json"
rgbasm -o build/dx.o src/dx.asm
rgblink -O build/base.gb -o build/dx.gb -m build/dx.map -n build/dx.sym build/dx.o
python3 tools/patch_obj.py build/dx.gb "src/moods/$V.json"
rgbfix -c -f hg build/dx.gb 2>/dev/null
cp build/dx.gb "out/Batman-DX-$V.gbc"
python3 tools/mkips.py build/base.gb build/dx.gb "out/Batman-DX-$V.ips"
(shasum "out/Batman-DX-$V.gbc" 2>/dev/null || sha1sum "out/Batman-DX-$V.gbc")
