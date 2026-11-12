# Vegetable Soup: MARS MLAP rehabilitation game

Godot 4.6. Press F5 to play. The mouse is the arm; the left button or Space is the grip.
Hold the cursor over a vegetable for one second to pick it up. Carry it over the pot to
drop it in automatically. Grip the spoon to stir along the MLAP guide.

Each 60-second trial loops: carry 3 vegetables to the pot, stir 2 laps, repeat.

Pressing the grip over a vegetable picks it up at once, so hovering is the alternative for
patients who cannot hold the grip. A carried vegetable drops in once it is well inside the
pot, not when it only brushes the edge; opening the grip elsewhere sends it back to its crate.

## Customer and stir patterns

Each soup is a new order from a customer at the serving window: "Soup stirred in a figure
eight, please!" The order ticket under the timer shows the path to follow. The patterns come in
this order and then repeat (`scripts/stir_patterns.gd`): circle, wide oval (side-to-side reach),
tall oval (forward-and-back reach), square (sharp turns), figure eight (changing direction) and
diamond (reaching to four points). The left arm gets the mirror image of each, so the first move
is always anterior.

While stirring, the customer's face follows how it is going: happy when accurate, worried when
off the line or slow, confused when going the wrong way. When the soup is done they taste it,
give 1 to 3 stars and one specific tip (`scripts/customer_feedback.gd`), and leave a tip of 50
points per star. The results screen shows the customers' average stars.

The path is scored by distance to the nearest point on it, so any closed shape works. There are
eight checkpoints round each loop, and progress can only run about one checkpoint ahead of the
last one reached, so shortcuts and wiggling where a path crosses itself earn no laps.

## Pictures

Vegetables are in `assets/veg/`, cut from the sheet in `assets/source/vegetable_sheet.png` by
`tools/slice_vegetables.py`. Props (bowls, shakers, knife block, cabbage and so on) are in
`assets/props/`, rendered from the Kenney Food Kit models (CC0, in `assets/kenney_food_kit/`) by
`tools/render_models.gd`, then given a matching dark outline by `tools/outline_props.py`. The
game loads pictures through `scripts/sprites.gd`, and anything missing falls back to a plain
shape. To add a vegetable, put a transparent PNG in `assets/veg/` and add its name to
`Ingredient.Kind`.

## Look

The kitchen is drawn in a 3/4 view entirely in code, with no image files:
`background.gd` (wall, shelf, counter, stove, crates, trays), `cooking_pot.gd` (pot, broth,
flames, steam), `hud_art.gd` (sign, timer, score stars, accuracy dial) and `paint.gd` (shared
drawing helpers). The stir ring is drawn as an ellipse (`StirTracker.aspect`) but scored as a
true circle.

## Node trees

```
Main (Node2D) main.gd                    scenes/main.tscn
├─ World (Node2D)                        disabled while tracking is lost
│  ├─ Background (Node2D) background.gd
│  ├─ Slots (Node2D)
│  │  └─ 8 × Marker2D                    plate positions
│  ├─ CookingPot                         instance of cooking_pot.tscn
│  ├─ Ingredients (Node2D)               vegetables are spawned here
│  ├─ Cursor                             instance of cursor.tscn
│  ├─ RoundTimer (Timer)                 the countdown
│  └─ NextRoundTimer (Timer)
└─ HUD                                   instance of hud.tscn

Cursor (Area2D) cursor.gd                scenes/cursor.tscn
└─ CollisionShape2D                       hover detection

Ingredient (Area2D) ingredient.gd        scenes/ingredient.tscn
└─ CollisionShape2D                       hover detection; progress ring is drawn by script

CookingPot (Area2D) cooking_pot.gd       scenes/cooking_pot.tscn
├─ CollisionShape2D
├─ Contents (Node2D)                     vegetables already in the pot
├─ StirTracker (Node2D) stir_tracker.gd  accuracy calculator and guide ring
├─ Spoon (Area2D) spoon.gd
│  └─ CollisionShape2D
└─ Splash (CPUParticles2D)

HUD (CanvasLayer) hud.gd                 scenes/hud.tscn
├─ TopBar (PanelContainer) → Row
│  ├─ ScoreLabel, TimeLabel
│  └─ AccuracyBox → AccuracyLabel, AccuracyBar (ProgressBar)
├─ ObjectiveLabel
├─ CenterPanel                           start and results messages
└─ TrackingBanner
```

`MarsInput` (`scripts/mars_input.gd`) is an autoload, not part of any scene.

## Collision layers

| Layer | Used by | Detects (mask) |
| --- | --- | --- |
| 1 Cursor | Cursor | Ingredients, Spoon |
| 2 Ingredients | Ingredient | nothing |
| 3 Pot | CookingPot | Ingredients |
| 4 Spoon | Spoon | nothing |

Cursor mapping lives in the `MarsInput` autoload. Feed `MarsInput.submit_sample(Vector2(x, y), grip)`
with normalized 0..1 coordinates from the patient's assessed MLAP range. `MarsCursor` maps these
to viewport pixels and applies optional smoothing. Ingredient hover progress is tracked there
(`ingredient_hover_seconds`, default 1 second); leaving the ingredient resets it. The grip remains
available for picking up the spoon and starting or restarting a trial.

## How accuracy is calculated

`deviation = |distance from pot centre − ring radius|`

| Deviation | Score |
| --- | --- |
| Up to `tolerance` (22 px) | 100% |
| Between `tolerance` and `max_deviation` (80 px) | Falls in a straight line |
| `max_deviation` or more | 0% |
| Moving against the arrows, at any deviation | 0% |

Each sample is weighted by the distance moved, so holding still neither earns nor loses
anything. Movement under `min_step` (4 px) is ignored as sensor noise. The progress bar shows
a rolling recent value, and the results screen shows the average for the whole trial.

Points are earned per radian travelled, scaled by accuracy, and only at 50% accuracy or above.
Laps only advance within `max_deviation`, so small circles near the centre don't count.

All of these values are exported on `StirTracker` and `CookingPot` for tuning per patient.

## Connecting the MARS device

Only `scripts/mars_input.gd` knows where input comes from. Call `submit_sample()` once per
telemetry packet, and the mouse simulation switches off automatically:

```gdscript
MarsInput.training_side = MarsInput.Side.RIGHT  # or LEFT, from the patient profile
Robot.sample_received.connect(func(packet: Dictionary) -> void:
	# The handle button is active-low: 0 means pressed.
	MarsInput.submit_sample(Records.normalized_position("MLAP"), packet.button == 0)
)
```

`Robot` and `Records` are the autoloads in `MARS-HOMER/Godot`. If samples stop for 2 seconds,
the game holds, the trial clock stops and a warning appears. It resumes when samples return.

## Check on a real device

The game has only been tested with simulated input, not on a connected MARS unit.

- **Button conflict:** in a MARS HOMER trial, tapping the handle button pauses and holding it
  for 1.5 s finishes and saves. Those gestures must be turned off for this game, or carrying a
  vegetable will end the trial.
- **Directions:** the code assumes screen right is lateral for a right arm and screen up is
  anterior. Confirm this against the arm, because a mistake would train the path in reverse.
- **Tuning:** the default tolerance and noise values are starting points, not clinically
  validated. Accuracy is measured in screen pixels within the patient's assessed range, so a
  screen circle is an ellipse at the hand when their ML and AP ranges differ.

## Tests

```
godot --headless --fixed-fps 60 --path . res://tests/game_test.tscn
```

The test plays the real game scene through `MarsInput.submit_sample()`, the same call the
device will use.

## Chef bot

A small hovering robot chef (`scripts/chef_bot.gd`, created by `main.gd`) keeps the patient
company. It flies to the side nearest the next vegetable and points at it, points at the pot
while one is carried and at the spoon when it's time to stir. It cheers each vegetable in, its
face follows the customer's mood while stirring, and it celebrates each soup with a short line
("Semma! 3 stars!"). Its lines are in `main.gd`.
