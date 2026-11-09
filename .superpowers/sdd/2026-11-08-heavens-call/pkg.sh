#!/usr/bin/env bash
# usage: pkg.sh <snapdir> <outfile> <title>   — diff snapshot -> current tree (text files), new files appended
cd /d/DevEnv/GDOT/environment-lab
S="$1"; O="$2"
{ echo "# $3 (diff -ruN --strip-trailing-cr, snapshot -> current)"
  for p in scripts scenes tests tools addons project.godot main.md README.md docs assets/materials assets/shaders assets/blender; do
    [ -e "$p" ] || continue
    diff -ruN -U10 --strip-trailing-cr -x '*.uid' -x '*.import' -x '*.blend*' -x 'superpowers' "$S/$p" "$p"
  done
  echo "# new/changed binary or audio files:"; find assets/meshes assets/audio assets/grass -newer "$S/project.godot" -type f 2>/dev/null
} > "$O"
wc -l "$O"; grep '^+++ ' "$O" | cut -f1
