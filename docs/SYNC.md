# Backend readiness

Nothing here is implemented — this is the note Phase 3 owes a future sync adapter (PLAN §7,
Phase 3.5). Hypertime is local-only today: one SQLite file, no network code, no account.

## What already exists

Every mutation that changes user data is appended to `change_log` inside the same transaction
as the change itself, so the log can never disagree with the tables:

```sql
CREATE TABLE change_log (
  id      INTEGER PRIMARY KEY AUTOINCREMENT,  -- monotonic, gap-free per device
  at      REAL NOT NULL,                      -- unix seconds, wall clock
  kind    TEXT NOT NULL,
  payload TEXT NOT NULL                       -- JSON object, keys below
);
```

| `kind` | `payload` keys | Meaning |
|---|---|---|
| `project.create` | `id`, `name` | New project. |
| `project.rename` | `id`, `name` | New name (already trimmed and capped at 200 characters). |
| `project.archive` | `id`, `archived` (`"0"`/`"1"`) | Archive flag flipped. |
| `project.delete` | `id` | Project and, by cascade, all of its entries are gone. |
| `entry.set` | `project`, `day`, `seconds` | A total was **set** to `seconds` (manual edit). |
| `entry.add` | `project`, `day`, `delta`, `seconds` | `delta` was **added**; `seconds` is the resulting total. |

`day` is a local `YYYY-MM-DD` string, never a timestamp, so a device moving between time zones
does not silently re-date existing work. `seconds` is always the post-write value, which lets a
consumer treat `entry.add` as either a delta or an idempotent state assertion.

Rows older than 90 days are pruned on launch (`Store.pruneChangeLog`). A sync adapter must
therefore push more often than that, or raise the retention window before shipping.

## How an adapter would consume it

1. Store a per-device `lastSyncedChangeID` in `app_state`.
2. On a timer and on `Store.changes`, read `SELECT * FROM change_log WHERE id > ? ORDER BY id`
   and push the batch. `change_log.id` is monotonic, so a crash mid-push only ever replays.
3. Advance `lastSyncedChangeID` only after the server acknowledges the batch.
4. Apply inbound changes through the existing `Store` methods so the local log records them
   too, and skip echoing rows that originated remotely (add an `origin` column for that —
   the current schema has no room for it, and adding one is a `v2` migration).

## What is missing for real sync

- **Identity.** Projects are local UUIDs; day entries are keyed `(project_id, day)`. Both are
  stable and safe to use as server-side keys, but there is no user or device identifier yet.
- **Conflict resolution.** Two devices editing the same `(project, day)` need a rule.
  `entry.set` is last-writer-wins by `at`; `entry.add` is commutative and should be replayed as
  a delta rather than a total. That distinction is the reason both kinds are logged separately.
- **Deletion tombstones.** `project.delete` is logged, but the cascade delete of its entries is
  not logged row by row. A server that mirrors entries must apply the cascade itself.
- **Clock trust.** `at` is wall-clock from the device and can move backwards. Order by `id`
  within a device and by a server-assigned sequence across devices, never by `at` alone.
- **The pending bucket never appears in the log.** It only exists in memory and in `app_state`
  until a commit turns it into an `entry.add`. That is deliberate: unattributed time is not data
  worth syncing.
