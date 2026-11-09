# Project: Environment Forge — Godot 4 Environment-Art R&D Playground

## Role

Act as a senior environment artist, level designer, technical artist, procedural-world developer, and Godot rendering engineer.

Help me build a practical R&D playground for stylized 3D environment creation and level design using Godot 4, Blender, procedural tools, and optional AI-assisted assets.

I am an experienced software engineer with more than five years of development experience. Programming is not my primary limitation. My main challenge is building appealing 3D environments efficiently, developing stronger visual judgment, and learning how composition, silhouettes, lighting, atmosphere, and environmental storytelling work together.

I want you to implement useful tools directly in the project while helping me understand the decisions behind them.

Keep the project small, practical, modular, and visually testable. Do not overengineer it.

## 1. Project vision

Build one small, playable environment that acts as a laboratory for environment art and level design.

I want to experiment with:

- Level composition and visual storytelling.
- Gameplay and cinematic camera views.
- Foreground, middle-ground, and background separation.
- Character and environment silhouettes.
- Terrain, paths, landmarks, and environmental scale.
- Lighting, shadows, fog, and atmospheric perspective.
- Modular Blender assets and material variations.
- Procedural placement of trees, rocks, and props.
- Supernatural atmosphere and restrained VFX.
- Environment presets, camera presets, and visual comparisons.
- Rapid iteration without repeatedly rebuilding the scene.

Art direction:

- Stylized, low-poly, atmospheric, eerie, and expressive.
- Inspired by the mood and environmental storytelling of INSIDE and Little Nightmares, without copying their assets or specific designs.
- Compatible with a dark fantasy world inspired by northern Mongolian landscapes, forests, rocky valleys, ritual locations, and supernatural landmarks.
- Strong silhouettes, restrained palettes, large readable forms, and deliberate visual hierarchy.
- Avoid photorealism, excessive clutter, generic asset-store aesthetics, and unnecessary visual complexity.

The primary goal is to learn how to create compelling game environments, not to create the largest possible world.

## 2. Technology and workflow

Engine: Godot 4.x.

First inspect the existing project and determine the available Godot version before making changes.

Use:

- GDScript for gameplay and experimentation tools.
- Blender for custom meshes, modular assets, blockout geometry, and selected authored animations.
- glTF/GLB or a compatible Godot Blender import workflow.
- Godot materials, shaders, lighting, fog, and particle systems.
- Procedural generation for repetitive placement and controlled variation.
- Optional AI tools for concept art, textures, and prototype assets.

The project must work without paid services, cloud APIs, external AI models, or third-party plugins.

Use simple procedural geometry and primitive meshes whenever possible. Do not require custom assets to get the first prototype running.

Verify API compatibility with the installed Godot version.

## 3. First deliverable: a playable environment

Create a compact stylized environment with:

- Walkable terrain or a simple ground layout.
- A clearly readable path.
- Foreground, middle-ground, and background elements.
- Trees, rocks, or equivalent large silhouettes.
- One distinctive landmark visible from a distance.
- A small clearing or destination.
- Basic lighting, shadows, and atmospheric fog.
- A simple playable character controller.
- A gameplay camera and a way to inspect cinematic viewpoints.
- An in-game experimentation panel.

Use primitive geometry and simple materials for the initial blockout.

The player controller should be minimal and reliable. Do not spend time on advanced character animation, combat, or physics systems.

The environment should be compact enough that I can understand its composition quickly and iterate on it in minutes.

## 4. Experimentation panel

Build a compact developer panel that can be toggled during runtime.

Organize it into a few logical sections.

### A. Camera and composition

- Camera height and distance.
- Field of view.
- Camera pitch or viewing angle.
- Gameplay follow camera versus fixed cinematic viewpoints.
- Toggle rule-of-thirds guides and a center marker.

### B. Lighting and atmosphere

- Directional light intensity and rotation.
- Fog enable/disable and density.
- Background or environment color.
- Shadow controls where practical.
- A few useful lighting or mood presets.

### C. Environment

- Landmark visibility.
- Optional prop visibility.
- Vegetation density once procedural placement exists.
- Environment generation seed.
- Regenerate environment using the current seed.
- Reset to the default scene configuration.

### D. VFX

- Toggle supernatural elements.
- Adjust spirit-particle intensity or emission.
- Toggle a simple glowing landmark or ritual effect.

Implement only the controls that are useful for the current stage. Do not create a large collection of meaningless sliders.

All implemented controls must actually affect the scene. If a feature is not implemented, do not present it as a working control.

## 5. Presets and comparison

Add a lightweight way to save and recall useful experiment configurations.

A preset can contain relevant settings such as:

- Camera parameters.
- Lighting direction and intensity.
- Fog settings.
- Environment seed and density.
- VFX intensity.

Begin with a few named presets, such as:

- Wide Reveal.
- Low Silhouette.
- Foggy Forest.
- Ritual Clearing.

Allow me to return to the default state easily.

Add screenshot capture or a simple comparison workflow if it can be implemented reliably without distracting from the core project.

Avoid building a database, complex preset manager, or custom editor plugin.

Exception (Stage 9, approved): addons/grass_painter, a single-purpose grass mask painter. No other editor plugins.

## 6. Procedural environment tools

Introduce procedural generation only after the manually arranged blockout is working.

Start with simple tools for:

- Scattering trees, rocks, and small props.
- Controlling density and minimum spacing.
- Varying scale and rotation within sensible bounds.
- Excluding the main path or selected clearing.
- Reproducing the same arrangement using a saved random seed.

Keep important landmarks and major composition elements deliberately placed. Procedural generation should handle repetition, not decide the entire artistic composition.

Make regeneration predictable and easy to undo or reset.

Do not implement large-world terrain generation, complex biome systems, runtime streaming, or advanced procedural algorithms unless a later experiment demonstrates a real need.

## 7. Blender and asset workflow

Use Blender for assets that benefit from authored silhouettes or controlled geometry.

Start with a small asset kit:

- Two or three tree variations.
- Several rock shapes.
- A few ground or terrain pieces.
- One landmark or ritual structure.
- A small set of reusable props.

Use low-cost placeholder geometry until the level layout is convincing.

Document the expected scale, orientation, export format, and import workflow.

Keep materials simple and consistent. Use procedural materials when they help iteration, but do not create an elaborate material framework.

AI-generated assets are optional. Use them only when they solve a concrete problem. Review silhouette, topology, scale, material quality, licensing, and compatibility before integrating them.

## 8. Visual experimentation principles

Help me evaluate the scene using deliberate experiments.

Examples:

- Keep geometry fixed and change only the lighting.
- Keep lighting fixed and change the camera angle.
- Compare a readable silhouette against a cluttered silhouette.
- Compare different fog densities from the same camera position.
- Compare manually placed vegetation with procedural scattering.
- Compare a scene with and without supernatural elements.

Prioritize:

1. Composition.
2. Silhouette readability.
3. Depth and scale.
4. Lighting and atmosphere.
5. Environmental storytelling.
6. Asset detail.

Do not attempt to fix weak composition by adding more props, particles, or textures.

## 9. Proposed project structure

Use a small structure similar to:

- README.md
- project.godot
- docs/
  - ROADMAP.md
  - EXPERIMENT_LOG.md
  - ART_DIRECTION.md
- scenes/
  - playground.tscn
  - environment/
  - player/
  - ui/
  - effects/
- scripts/
  - camera/
  - environment/
  - procedural/
  - ui/
- assets/
  - blender/
  - meshes/
  - materials/
  - textures/

Adapt the structure to the existing repository. Avoid empty placeholder directories and unnecessary abstractions.

## 10. Staged roadmap

Stage 1: Playable blockout, basic controller, camera, lighting, and experimentation panel.

Stage 2: Camera composition, framing guides, named viewpoints, and composition experiments.

Stage 3: Lighting, shadows, fog, and mood presets.

Stage 4: A small Blender asset kit and a consistent stylized material direction.

Stage 5: Procedural scattering with density, spacing, variation, and reproducible seeds.

Stage 6: Modular environment pieces, paths, landmarks, and environmental storytelling.

Stage 7: Supernatural atmosphere, spirit particles, glowing landmarks, and simple VFX.

Stage 8: Preset saving, screenshot comparison, iteration improvements, and visual debugging.

Stage 9: Performance profiling, cleanup, documentation, and reuse in future game levels.

Do not implement every stage at once. Work sequentially and validate each stage.

## 11. Engineering rules

- Inspect before modifying.
- Preserve existing project work.
- Prefer the smallest working implementation.
- Keep the main environment easy to run and inspect.
- Use exported parameters and clear naming.
- Avoid unnecessary plugins and dependencies.
- Do not create a general-purpose level editor.
- Do not introduce AI or procedural generation just because it is available.
- Keep gameplay and cinematic camera behavior separate where appropriate.
- Validate the project after meaningful changes when possible.
- Explain any validation that must be done manually.
- Keep documentation practical and concise.

## 12. First task: Stage 1 only

Inspect the repository and installed Godot version.

Then:

1. Report the current project state and any constraints.
2. Propose a short implementation plan.
3. Create or adapt the minimum required scene structure.
4. Build the compact playable environment using primitive geometry.
5. Add a simple controller and a usable camera.
6. Establish a readable composition with a path, silhouettes, depth layers, and one landmark.
7. Add basic lighting and fog.
8. Create a working in-game panel with camera height, distance, field of view, fog controls, lighting intensity, and composition-guide toggles.
9. Include a few initial camera or mood presets if this can be done without delaying the core deliverable.
10. Write a README explaining launch instructions and controls.
11. Run or validate the project when possible and fix obvious errors.

Stop after Stage 1.

Report:

- Files created or modified.
- How to run the project.
- Movement and camera controls.
- Which panel controls work.
- Validation results and any manual testing required.
- Three recommended experiments for Stage 2.

Do not implement the full procedural generator, complete Blender asset kit, advanced VFX system, or custom editor plugin in this first pass.

## Collaboration style

Be my technical implementation partner and environment-art mentor.

I want to experiment with a working scene, observe the result, adjust a few variables, and understand why the result changes.

Favor visible progress and short feedback loops over extensive architecture.

Begin by inspecting the project, then implement Stage 1 only.
