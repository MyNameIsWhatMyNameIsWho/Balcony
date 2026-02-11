# Balcony — Quick Game Design Document (GDD)

## High concept
A short, session-based narrative game about a depressed man who escapes into watching strangers through windows. Each window is a contained vignette that reveals a fixed piece of his inner world. The story is fixed; **access is conditional** (fragments/avoidance), but there are no branching timelines.

## Player fantasy / tone
Quiet voyeurism, melancholy curiosity, and the discomfort of recognizing yourself in other people’s moments.

## Core loop (15–25 minutes, no saves)
- **Start (Flat / intro)**: Inner-voice dialogue sets mood; player regains control.
- **Explore (optional)**: Walk in the flat; interact with a few objects for inner-voice lines.
- **Balcony**: Enter the balcony trigger → camera transitions to building view → cursor-enabled window selection.
- **Window vignette template (8 total)**:
  - Hover a window → short inner thought (hover line)
  - Click a window → camera eases to its authored close-up
  - Vignette text (typewriter + later VO)
  - **Binary choice**: Engage (A) / Look away (B)
  - Immediate outcome + reflection **or** memory fragment (at most 1 per window)
  - Return to selection view (smooth transition)
- **End**: After all windows are resolved, a **“Stop watching”** button appears → Ending screen.

## Rules (core principle)
- **Windows**: exactly **8** windows.
  - 5 normal
  - 2 “special” (curtains / noticed)
  - 1 emotionally neutral (pacing/contrast)
- **Choices**: exactly **2** per window.
  - Always: **Engage** / **Look away**
  - Resolves immediately; no cross-window dependencies.
- **Memory fragments**: total **6**.
  - A window can unlock **at most 1** fragment.
- **Avoidance**:
  - “Look away” increments avoidance counter.
- **Endings** (3 total + optional avoidance override):
  - 0–1 fragments → Routine
  - 2–4 fragments → Partial understanding
  - 5–6 fragments → Confrontation / break
  - Optional override: extreme avoidance can replace Routine with “Accident” (text-only), if enabled in endings data.

## Controls (current)
- **Move**: WASD
- **Look**: mouse
- **Interact / continue**: E
- **Choice**: Mouse or A/D (left/right)

## Camera & presentation
- **Flat camera**: first-person feel with subtle “breathing”.
- **Balcony selection camera**:
  - Smooth ease-in/out transitions.
  - “Screen floating”: camera drifts subtly based on cursor position (clamped, smoothed).
- **Per-window cameras**: each window has an authored `Camera3D` for close-up framing.
- **StoryScreen image logic**:
  - In selection view: each window displays a **base** image (or **seen** image if resolved).
  - On click/zoom: selected window switches to **cover** image; StoryScreen pixelation animates during camera motion, then becomes clear on arrival.

## UI / UX
- **Dialogue UI**:
  - Typewriter text + (future) VO hooks.
  - Hover line for window thoughts (non-locking).
  - Intro/interactions show in “blocks/pages” rather than one line per press.
- **Choice overlay**:
  - Full-screen split halves as buttons (left/right).
  - Cinematic hover highlight (scale/tilt/float/brighten).
- **Ending UI**:
  - Shows final ending lines.
  - Restart / Quit.

## Content pipeline (data-driven)
All narrative content is loaded from JSON via `ContentDB`:
- `res://data/windows.json`: window entries keyed by `window_id`
- `res://data/flat.json`: interactable entries keyed by `object_id`
- `res://data/intro.json`: array of strings (blocks separated by empty lines)
- `res://data/endings.json`: endings with fragment ranges + optional avoidance trigger

## Game state (session-based)
Tracked by `GameState`:
- fragments collected
- resolved windows
- windows that granted fragments
- avoidance count

## Art direction (1 sentence)
Low-detail, pixel-filtered realism with muted colors and soft lighting—cozy surface, heavy subtext.

## Sound plan
- **Typewriter**: subtle per-character “tick” (already supported).
- **Ambient**: room tone, distant city hum, balcony wind, occasional far traffic.
- **UI**: minimal clicks/confirm sounds; avoid “gamey” blips.
- **Voice-over (later)**:
  - Option A: inner-voice VO that matches each dialogue block.
  - Skipping text should also stop VO cleanly.

## Level/scene structure (current)
- `scenes/title.tscn`: title + Start button
- `scenes/flat.tscn`: main play scene (flat + balcony + building + windows + UI)

## Stretch goals (later)
- Better window “clips” (2D/3D micro-animations) behind the cover image.
- Light progression in ambience as more windows are resolved.
- Accessibility: text speed slider, font size option, subtitles toggle for VO.

