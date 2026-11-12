# Colour the Picture – MARS rehab game (Godot 4.6)

Open `project.godot` in Godot 4.x and press F5. Esc quits. No art/audio assets needed (all procedural).

## Node tree (built by `scripts/level_manager.gd`, root = `scenes/main.tscn`)
```
Main (Node2D)  <- LevelManager.gd
├ Background (TextureRect, gradient)
├ Paper (Panel)                        white drawing sheet
├ Canvas (Node2D)
│  └ <Region> x8 (Area2D, ColorRegion.gd)
│     ├ Fill (Polygon2D, white, tinted via modulate)
│     ├ Hitbox (CollisionPolygon2D)
│     ├ Outline / detail lines (Line2D)
│     └ Burst (CPUParticles2D)
├ ReferenceFrame (Panel) > ReferenceImage (TextureRect <- SubViewport texture)   top centre
├ PaletteBacking (Panel), Palette (VBoxContainer) > PaletteButton x6 (TextureButton)   right edge
├ HUD: Label, ProgressBar, hint PanelContainer, "Play again" Button, Confetti
└ CanvasLayer > BrushCursor (Node2D)
```

## 50 picture templates
Pictures live in `scripts/level_data.gd` (`SPECS`). Each is just a background colour, optional ground, and a list of
reusable objects (`[kind, x, y, scale, colour]`), so adding a new one is a single line.
- Every coloured part = **+1 score** (star badge, top-left; session total).
- After a picture is finished, "Well done!" + confetti, then the next picture loads automatically
  after `next_picture_delay` seconds (default 4.5). Progress is saved, so the game resumes where it stopped.
- Therapist keys: **Left / Right arrow** = previous / next picture.
- Colouring order is bottom-to-top (background first), so there are no hidden or unreachable shapes.

## Bindu, the cheering buddy (`scripts/buddy.gd`)
A paint-drop character in the bottom-left corner. It only ever encourages - it never reacts to mistakes.
- Eyes follow the brush, blinks, gently bobs; turns the colour of the selected paint.
- Hops and cheers when a shape is painted, dances when the picture is finished.
- Waves "Hi!" when the brush comes near it.
- If there is no progress for `buddy_idle_seconds` (default 14 s), it looks at the target and gives a friendly nudge.
- Change or translate its lines in `Buddy.LINES`. Turn it off with `show_buddy` on the `Main` node.

## Background & instructions
- `scripts/background.gd`: soft sky, sun glow, slowly drifting clouds and birds, pastel hills with trees/flowers,
  gently rising light specks. Turn motion off with `animated_background` on `Main`.
- Written instructions are hidden by default and fade in only after `hint_delay_seconds` (default 6 s) without
  progress; they fade out again as soon as the player picks a colour or paints a shape.

## Accessibility / MARS design
- **Dwell selection**: hold the cursor on the glowing target (default 1.2 s). No click needed. Click also works.
- Errorless: only the glowing colour / shape reacts; nothing can be "wrong"; no timers or fail states.
- Tremor tolerance: cursor low-pass filter (`cursor_follow_speed`), 16 px grace margin on swatches, dwell progress drains slowly when slipping off.
- Huge targets (130 px swatches, whole-region fills), high contrast outlines, big text.
- Tweak in the inspector on `Main`: `dwell_seconds`, `cursor_follow_speed`, `celebration_seconds`.
- MARS planar (MLAP) motion maps to cursor X/Y; the game only reads the OS mouse position.

## Editor notes
- Region fill is white; colouring = `modulate` (done in `ColorRegion.fill_with`).
- To add pictures: add entries to `scripts/level_data.gd` (`poly`, `details`, `color`, `step`; list order = draw order).
- Signals on LevelManager: `color_required`, `color_selected`, `region_completed`, `level_completed` (hook up logging for therapists).
