# Asset pipeline (Blender → Godot)

## Source of truth

- `assets/blender/build_kit.py` is a procedural builder. It is the real source of every kit asset.
- `assets/blender/environment_kit.blend` is its output, saved for inspection and hand-tweaking.
- `assets/blender/` contains a `.gdignore`, so Godot never tries to import the `.blend` (that
  would require a Blender path in Godot's editor settings).

**To rebuild:** open the `.blend` (or any Blender file), then go to *Scripting* → open
`build_kit.py` → *Run Script*. It wipes and rebuilds the `Kit` collection, exports one GLB per
asset to `assets/meshes/`, and saves the `.blend`. Godot re-imports the changed GLBs the next time
the editor gets focus.

If you hand-edit an asset in the `.blend`, re-running the script **overwrites** your edits. To
keep a hand-made asset, move it out of the `Kit` collection and export it yourself using the
conventions below.

## Conventions

| Rule | Why |
| --- | --- |
| 1 unit = 1 m, Z up in Blender (the exporter converts to Godot's Y up) | Kit pieces match the player (~1.8 m) and the blockout |
| Origin at the base centre; ground contact at z = 0 | Instances drop onto the ground with y = 0 |
| One root Empty per asset, named like the file (`tree_larch`) | The GLB root node gets that name |
| Material names = palette names: `foliage`, `larch`, `bark`, `deadwood`, `rock`, `monolith`, `ground`, `cloth`, `cloak`, `rusted_metal`, `weathered_wood` | Colours live in Godot. `kit_asset.gd` swaps each imported material for `res://assets/materials/<name>.tres` |
| Flat shading, low poly (≈ 50–500 tris for props/trees, a few thousand for the landmark) | The faceted shader rebuilds normals per face anyway |
| Parts of one tree share one mesh (trunk and foliage = two material slots of one object) | Wind sway and tint variation stay coherent across the tree |

## Collision (Godot name suffixes)

| Object name ends with | Godot creates | Used for |
| --- | --- | --- |
| `-col` | mesh + trimesh (concave) static body | ground mounds (walkable) |
| `-convcol` | mesh + convex static body | rocks, props |
| `-convcolonly` | collision only, invisible | tree trunks (crowns shouldn't block anything) |

The landmark has no imported collision. Its existing cylinder `Landmark/Body` blocks the outcrop.

## Using an asset in Godot

Each GLB has a wrapper scene in `scenes/environment/kit/<name>.tscn`. The wrapper is a `Node3D`
running `kit_asset.gd` with the GLB instanced as a child. **Always place the wrapper, not the
GLB**, otherwise the palette materials (and with them sway, tint variation and fog response) are missing.

Per-material look settings are in `assets/materials/*.tres`:
- `sway`: wind bend. 0 = rigid. All parts of one object must share the same value.
- `tint_variation`: per-object brightness and temperature jitter, so 80 copies of one tree
  don't read as copies.

A kit wrapper placed far above y = 0 (the Heavens call mountain) needs `height_from_origin = true`
on its `kit_asset.gd` root. Sway and the contact shade then grow with height above the piece's own
origin rather than world height. It is off by default, which keeps the playground unchanged.

## Adding a new asset

1. Write a builder function in `build_kit.py` (or model it by hand following the conventions),
   then add it to `ASSETS`.
2. Run the script. In Blender, check silhouette, scale (next to a 1.8 m reference) and
   orientation.
3. Copy any wrapper in `scenes/environment/kit/`, point it at the new GLB, and place it.
4. Check it in the game from the main viewpoints, with Notan and Squint on. A new asset has to
   help the composition, not just exist.

## AI-generated or downloaded assets

These are optional, and only worth it when they solve a concrete problem. Before integrating
one, check the following in this order:
1. **Silhouette** against the kit at gameplay distance.
2. **Scale.**
3. **Poly count and topology.**
4. **Material:** re-assign it to a palette material name, and drop its textures.
5. **Licence.**

If it needs textures to look right, it doesn't belong in this art style.
