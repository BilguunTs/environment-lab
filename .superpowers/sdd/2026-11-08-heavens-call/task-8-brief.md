### Task 8: Audio files

**Files:**
- Create: `assets/audio/*.ogg` (whatever can be fetched), `assets/audio/CREDITS.md`, and
  `assets/audio/NEEDED.md` (only if some files are missing)

**Interfaces:**
- Consumes: the file names in Global Constraints and `assets/audio/README.md` (Task 4).
- **Rules:**
  - **CC0 only.** Verify the licence on each file's own page (a site-wide claim isn't enough).
  - Natural field recordings: real wind, real gravel and rock steps, distant thunder with long
    tails. No music, no designed "horror" stingers, no synthesis.
  - Convert to Ogg Vorbis with Godot-compatible import. Loops loop cleanly: no click at the seam.
    Trim or crossfade if needed.
  - Footsteps are 4 variations each, sounding like a light person walking slowly.

- [ ] **Step 1: Find and download.** Try direct-download CC0 sources (for example OpenGameArt
  entries marked CC0, or other sites with plain download links and a per-file CC0 statement). Use
  `curl` with the file's direct URL. Don't use anything behind a login.
- [ ] **Step 2: Credits.** For each file you keep, write a row in `CREDITS.md`: file name, source
  page URL, author, licence (`CC0 1.0`), and any edits made.
- [ ] **Step 3: The rest.** For each file name you couldn't get, write a row in `NEEDED.md`: what it
  should sound like, loop or one-shot, rough length, and search terms. Missing files stay silent
  in the level (Task 4).
- [ ] **Step 4: Run** `--import`, then `--only=heavens`. Expected: all PASS, with no import errors.
- [ ] **Step 5: Listen-through by capture.** Play the level headless for 20 s at progress 0.1 and
  0.7, and confirm in the log that each present file loaded. Ledger which files exist and which
  are needed.
- [ ] **Step 6: Checkpoint.** Run the full suite windowed and headless. Both green.

