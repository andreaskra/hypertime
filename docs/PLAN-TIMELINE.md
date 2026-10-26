# Backlog — the 24-hour timeline

> **Status: built, 2026-10-26.** Built as written except where noted below; the §8 questions
> were answered by building the recommended option in each case, and those answers are now
> decisions in `DECISIONS.md` rather than open questions. What changed in the building:
> TLD-02's backfill was **not** done (no history is reconstructed from `change_log` — the
> strip starts empty and fills in), the marks are drawn in one `Canvas` rather than as 144
> views, and the magnified mark grows mostly in height because width past about 1.5× merges
> the bulge into a blob. Drafted 2026-10-25 from a spoken brief. Same conventions as
> `PLAN.md`: **TL-xx** requirements, **TLD-xx** decisions, **TLA-xx** assumptions. Assumptions
> are what I will build unless told otherwise. §8 is the short list of things I need answered
> before starting.

A strip between the amount and the TASKS section showing the last 24 hours as a row of evenly
spaced marks, one per fixed time bracket, each coloured by the project tracked in it. Hovering
magnifies the mark under the cursor the way the Dock magnifies its icons, and names what it is.

The purpose, in the user's words: *"if I haven't been at the computer for a while and I come
back and I see there's been 2 hours tracked, I want to see how those 2 hours allocate"* — and,
just as much, *"whether the app has correctly identified the idle time as such or whether it
has tracked it."* The second half is the harder requirement and it drives most of what follows:
**the strip has to be able to show time that was *not* tracked, and why.**

---

## 1. The blocker: this data does not exist yet

`day_entry` and `task_entry` are **daily totals** — `(project, day, seconds)`. Nothing anywhere
records *when* within a day a second was attributed. The timeline cannot be built from the
current schema at any resolution.

`change_log` is a partial substitute and worth knowing about:

| source | what it gives | good enough? |
|---|---|---|
| `task.add` rows | project, seconds, real timestamp, every 15 s flush | yes — near-live resolution |
| `entry.add` rows | project, seconds, timestamp **of the commit** | approximate: the seconds happened across the interval *before* the write, so they have to be spread back over it |
| idle | nothing at all | **no** — and this is the half the user actually wants to audit |

- **TL-01** A new table records attribution per time bracket. Sketch:

  ```sql
  CREATE TABLE slice (
    bucket_start  REAL NOT NULL,        -- unix time, aligned to the grain
    kind          TEXT NOT NULL,        -- tracked | idle | paused
    project_id    TEXT REFERENCES project(id) ON DELETE CASCADE,   -- NULL unless tracked
    seconds       INTEGER NOT NULL,     -- within this bucket, so a mixed bucket is >1 row
    PRIMARY KEY (bucket_start, kind, project_id)
  );
  ```
  Migration `v3-slices`. The engine writes on the same flush it already does, so this adds a
  write path, not a timer.
- **TLD-01** **Retention 7 days.** ~1000 rows at the grain below; nothing. The strip shows 24 h
  but a week in the table costs nothing and leaves the door open to the same strip in Reports.
- **TLD-02** **No backfill beyond what `change_log` can honestly reconstruct**, and that only
  for `tracked` — spreading each `entry.add` back across the interval since the previous one,
  and taking `task.add` rows at their timestamps. Idle and paused are simply absent before the
  feature ships.
- **TLA-01** Say so on screen rather than drawing a lie: buckets with no row at all render as
  the strip's empty track, which already means "nothing known about this time" (§4).

  **Consequence worth stating plainly: on the day this ships the strip is mostly empty.** It
  fills in as the app runs. There is no way around that short of inventing history.

## 2. Resolution

The strip is the popup's content width: 380 − 2 × 16 = **348 pt** for 1440 minutes.

| bracket | marks | pitch | a single 10-minute idle gap |
|---|---|---|---|
| 5 min | 288 | 1.21 pt | 2 marks — invisible |
| **10 min** | **144** | **2.42 pt** | **1 full mark** |
| 15 min | 96 | 3.63 pt | majority of 1 mark |
| 30 min | 48 | 7.25 pt | a third of 1 mark — lost |

- **TLD-03** **Ten-minute brackets, 144 marks.** It is the coarsest grain at which one default
  idle timeout (10 min) occupies a whole mark, and the audit question is the point of the
  feature. 30-minute marks look much better and answer the wrong question.
- **TLA-02** The idle timeout is a setting, so a user who sets it to 3 minutes gets gaps
  shorter than a bracket. Those show only where they win the bucket (§3), and the hover readout
  tells the truth regardless.
- **TLD-04** A mark is a **uniform-height rounded bar ~2 pt wide**, not a circle. At a 2.4 pt
  pitch a circle is a blur. This is the one place I am reading "dots" loosely: what was asked
  for was uniform brackets rather than bars of varying height, and that holds — every mark is
  the same size, and height never encodes a quantity.

## 3. Mixed brackets

- **TLD-05** **The dominant project colours the mark; the hover readout names every project in
  the bracket with its share.** The alternatives are worse: splitting the mark into segments
  contradicts the uniform-bracket idea and is unreadable at 2 pt, and blending the colours
  produces a muddy hue that means nothing and collides with other projects' real colours.
- **TLA-03** Ties go to the project that was running at the end of the bracket, so a run of
  marks does not flicker between two colours mid-stretch.
- **TLA-04** `idle` and `paused` compete for dominance like any project. Ten minutes of tracked
  work does not get to hide five minutes of idle inside it if idle is the larger share.

## 4. What the marks say

Four states, and they must be told apart without relying on colour alone:

| state | mark |
|---|---|
| tracked | filled, the project's colour |
| idle | hollow — the project colour as a thin outline, so "we noticed you were away" reads as present-but-empty |
| paused | filled, neutral grey |
| nothing known | no mark; the strip's own empty track shows through |

- **TL-02** Above or below the strip, one caption line, `Tokens.Typography.caption`. At rest it
  names the window ("last 24 hours"). While hovering it reads the bracket: `14:20–14:30 ·
  Design System`, or `14:20–14:30 · Design System 6m · idle 4m` when mixed.
- **TLA-05** Hour boundaries get a 1 pt tick under the strip, and midnight a slightly stronger
  one. Without them 144 identical marks have no scale at all.

## 5. Magnification (TL-03)

The Dock behaviour, with one change that matters:

- **TLD-06** **Marks do not move.** Every mark's centre stays pinned to its time; magnification
  grows height and width only, and magnified neighbours overlap, hovered one on top. The Dock
  pushes its icons sideways, which is fine for icons and wrong for a time axis — a timeline
  that slides under the cursor is lying about when things happened, and this strip exists to be
  trusted about exactly that.
- **TLA-06** Falloff over ±6 marks (±1 hour), smooth, hovered mark to roughly 1.8× height and
  2.5× width.
- **TL-04** Under Reduce Motion there is no magnification: the hovered mark takes a ring and
  the caption still reads. The feature must be usable at a glance with the mouse elsewhere.
- **TLA-07** Hit-testing is nearest-mark, not within-mark. At 2.4 pt nobody can hit a specific
  bracket on purpose, and magnification is exactly the affordance that makes that acceptable.

## 6. Colour, and the project list

- **TL-05** The project list below the strip carries each project's colour as a swatch, so the
  strip is readable without a legend of its own.
- **TLD-07** **Project colours become permanent**, stored as a `color_slot` column on
  `project`, assigned at creation as the lowest free slot. `Tokens.Series` stays the palette.

  This changes existing behaviour and needs a nod (§8). Today the chart assigns slots from the
  ranking of whatever period is on screen, so a project is blue in one week and orange in
  another — which was already a bit wrong and becomes untenable once a second view shares the
  colours. Pinning the slot fixes both and is strictly simpler.
- **TLA-08** Past the palette's slots a project takes the neutral "Other" colour, as the chart
  already does.

## 7. Where it sits

- **TL-06** Between `AmountField` and the TASKS section, inside the existing panel padding.
- **TLA-09** Height budget ~34 pt: 16 pt strip at rest, 12 pt caption, gaps. The magnified
  state grows into the gap above rather than reflowing anything — the popup must not change
  height on hover.
- **Implementation note:** check this against the panel's height clamp in
  `CheckInPanelController.layoutPanel`, which reads as `popupMaxHeight * 1.5` while the panel
  has been observed at 572 pt with a long task list. One of those two is wrong and it should be
  understood before adding another 34 pt.

## 8. What I needed before starting — and what was decided

1. **TLD-07** — permanent per-project colours. **Built.** `project.color_slot`, assigned at
   creation as the lowest free slot, backfilled by creation order. The Reports chart now reads
   the same slot, so a project is one colour everywhere and stays that colour.
2. **24 hours fixed.** Built fixed. `Timeline.window` is one constant if that changes.
3. **The same strip in Reports** — not built. Still worth doing; the table is there for it.
4. **TLD-03**'s ten-minute grain — kept. It looks denser than a coarser grain would, but a
   single idle timeout occupies a whole mark, which is the question the strip answers.
