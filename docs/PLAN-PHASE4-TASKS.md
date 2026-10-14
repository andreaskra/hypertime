# Phase 4 — Tasks (built)

> **Status: built as written.** The three decisions in §8 were taken as proposed. One thing the
> build added: when a task stops, the check-in clock *restarts* rather than firing the backlog it
> skipped — "the interval resumes" (TD-03) read as resuming, not catching up. A test pins it.


Everything else in the Phase 4 batch (day navigation, the chart, the overflow menu, the sticky
window, animations) is specified well enough to build directly. Tasks are not, so this is the
contract for them. Same conventions as `PLAN.md`: **T-xx** requirements, **TD-xx** decisions,
**TA-xx** assumptions. Assumptions are what I will build unless you say otherwise.

Confirmed already: a running task owns the clock (TD-01), unfinished tasks carry over (TD-06).

---

## 1. What a task is

- **T-01** A task is a named piece of work that belongs to exactly one project. The `+` button
  creates it under the project currently in the popup's field.
- **T-02** Tasks live in a todo list above the TODAY breakdown, with its own header.
- **T-03** Clicking a task starts tracking it. Clicking the running task again pauses it.
  Starting another task pauses the first. A paused task can always be resumed.
- **T-04** The checkmark on a row's left finishes a task. It leaves the list; its time stays.
- **T-05** A task can carry a timer. While it runs the row counts **down**. At zero the app
  interrupts (T-12).
- **T-06** A `⋯` menu per row: delete, pause/resume, move to project, set or clear a timer,
  rename.

## 2. Where the time goes

- **TD-01** (confirmed) **A running task owns the clock.** Its seconds are written straight to
  the task and to its project — live, no confirm step. The pending bucket does not accrue while
  a task runs; it resumes the moment no task is running.
- **TD-02** **Task time is a subdivision of project time, never an addition.** A tick on a
  running task writes to `task_entry` *and* to the project's `day_entry` in one transaction.
  Every existing report, total and CSV export stays correct and unchanged — the project number
  already contains its tasks. Invariant: for any project and day, the sum of its tasks'
  seconds ≤ the project's `day_entry.seconds`. The remainder is untasked time.
- **TD-03** **Check-ins are suppressed while a task runs.** "What are you working on?" is
  already answered; interrupting to ask again is noise. The interval resumes when the task stops.
  Consequence: a long task means no check-in for its duration — deliberate.
- **TA-01** Pausing a task leaves you with *nothing* running: the bucket starts accruing again
  and the next check-in attributes it the normal way. Pausing is not "back to the old project".

## 3. Data model

```sql
CREATE TABLE task (
  id            TEXT PRIMARY KEY,
  project_id    TEXT NOT NULL REFERENCES project(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  created_at    REAL NOT NULL,
  completed_at  REAL,                 -- NULL while open
  timer_seconds INTEGER,              -- NULL = untimed
  sort_order    REAL NOT NULL
);
CREATE TABLE task_entry (             -- mirrors day_entry, one row per task per local day
  task_id       TEXT NOT NULL REFERENCES task(id) ON DELETE CASCADE,
  day           TEXT NOT NULL,
  seconds       INTEGER NOT NULL DEFAULT 0 CHECK (seconds >= 0 AND seconds <= 86400),
  updated_at    REAL NOT NULL,
  PRIMARY KEY (task_id, day)
);
```

- **TD-04** `task_entry` is per-day, so a task worked on across three days contributes to three
  days' reports. Midnight splits exactly as `day_entry` does (D-06).
- **TD-05** Deleting a project cascades to its tasks. Deleting a task removes its `task_entry`
  rows **but not** the project's `day_entry` seconds — the time was really worked; only its
  attribution to a task is gone. The ⋯ menu's delete says so.
- **TD-06** (confirmed) Open tasks carry over. A task is not scoped to a day; it stays until
  finished or deleted. "Tasks for today" is the list you keep, not a list that empties at
  midnight.
- **TA-02** Finished tasks are kept in the database (for the breakdown and future reports), not
  deleted. Nothing surfaces them yet beyond their time; a "completed today" view is out of scope.

## 4. Engine

- **T-07** `TrackingStatus.tracking` gains an optional `taskID`. `.paused` keeps it, so resuming
  from sleep resumes the task.
- **T-08** The tick writes task seconds at the flush interval (15 s) and on every state change,
  rather than holding them in memory — a running task is already attributed, so there is nothing
  to lose by writing early, and a crash loses at most 15 s as it does today.
- **T-09** Quitting stops the task. Relaunching with `startTrackingOnLaunch` resumes the
  *project*, not the task: picking a task back up is a decision, not a default.
- **TA-03** A task started while the pending bucket holds unattributed time **does not** take
  that time. The bucket is left alone and the next check-in asks about it as usual.

## 5. The timer (T-05, T-12)

- **T-10** The ⋯ menu offers a timer with the same parser as everywhere else (`25m`, `1:30`).
- **T-11** While a timed task runs, its row shows the remaining time counting down, and the
  menu bar shows it too when "show elapsed" is on.
- **T-12** At zero the popup appears **focused** — this is an alert, not a nudge, so unlike a
  check-in it takes the keyboard — showing the task and two actions:
  - **Finish** — completes the task (T-04 animation) and stops tracking.
  - **Keep working** — clears the timer and keeps the task running untimed.
- **TA-04** The alert does not auto-hide and does not play a sound. It respects Do Not Disturb
  only in the sense that it is a window, not a notification.
- **TA-05** Overshooting is allowed: if the app was asleep when the timer expired, the alert
  appears on wake with the overshoot shown as a negative countdown.

## 6. Where tasks appear

- **T-13** In the popup: the task list above TODAY. Each row is checkmark · title · timer or
  elapsed · ⋯.
- **T-14** In the TODAY breakdown and the Reports day view: a task that has tracked time appears
  **indented under its project**, with its own time. The project row keeps the full total
  including its tasks.
- **T-15** The chart (built separately) treats tasks as part of their project; no task series.

## 7. Animation (T-16)

All within the existing motion budget and all collapsing to a 120 ms crossfade under Reduce
Motion, like everything else.

| Event | Motion |
|---|---|
| Task created | Pop: scale 0.9 → 1.04 → 1, 220 ms, with the row's height opening under it |
| Task completed | Strike-through sweeps left→right 180 ms, row greys, then slides out past the left edge and collapses, ≤ 400 ms total |
| Task deleted | Shrinks to nothing — scale and height to 0, 220 ms |
| Start / pause | Indicator and row tint crossfade 200 ms |
| Timer expiring | The countdown pulses once per second over the last 10 s |

## 8. What I need from you

1. **TD-03** is the one with teeth: no check-ins while a task runs. If you would rather keep
   being asked — "still on *Write the spec*?" — say so.
2. **TA-01**: pausing a task leaves nothing running. The alternative is falling back to the
   project you were on before.
3. **TD-05**: deleting a task keeps the time on the project. The alternative is removing it.

Everything else I will build as written.
