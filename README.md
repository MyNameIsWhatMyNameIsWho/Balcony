# Balcony

A short narrative game about a depressed man who watches strangers through apartment windows — and slowly recognizes himself in them.

**Engine:** Godot 4 · **Language:** GDScript · **Duration:** 15–25 min · **Solo project**

---

## About

The player explores a flat, steps onto the balcony, and observes 8 windows — each a self-contained vignette. For every window they choose to **Engage** or **Look away**. Some windows unlock memory fragments. After all windows are resolved, one of **3 endings** plays based on how many fragments were collected and how often the player looked away.

The story is fixed; the experience is shaped by what you choose to confront.

---

## Architecture

All narrative content is **data-driven via JSON** — no story text lives in code:

| File | Contents |
|------|----------|
| `data/windows.json` | 8 window entries: hover lines, vignette text, choices, outcomes, fragment triggers |
| `data/flat.json` | Interactable flat objects with inner-voice lines |
| `data/intro.json` | Intro dialogue blocks |
| `data/endings.json` | 3 endings with fragment ranges + optional avoidance override |

**Key systems:**

- **`ContentDB.gd`** — singleton that loads and exposes all JSON content at startup
- **`GameState.gd`** — session state: fragments collected, resolved windows, avoidance count; drives ending selection
- **`dialogue_manager.gd`** — typewriter text, block paging, hover lines, choice overlay
- **`balcony_trigger.gd`** — core game loop: camera transitions, window vignette flow, state updates
- **`window_selector.gd`** — cursor-driven window hover/selection with smooth camera drift
- **`rain_effect.gd`** — ambient GDShader particle effect

---

## Endings

| Fragments | Ending |
|-----------|--------|
| 0–1 | Routine |
| 2–4 | Partial understanding |
| 5–6 | Confrontation / break |
| — | Accident *(avoidance override, if enabled)* |

---

## How to run

1. Open the project in **Godot 4.1+**
2. Run `scenes/title.tscn`
3. Controls: WASD to move, mouse to look, E to interact, mouse click for choices

---

## Design document

See [`GDD.md`](GDD.md) for the full game design document — core loop, rules, content pipeline, and art/sound direction.
