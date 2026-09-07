# Decisions log

Append-only. One entry per decision that refines or deviates from `PLAN.md`.

| Date | Ref | Decision | Why |
|---|---|---|---|
| 2026-09-07 | — | Plan and design brief written; no code yet. | Kickoff. |
| 2026-09-07 | D-07 | Dock icon accepted as the price of Cmd+Tab. | User confirmed. |
| 2026-09-07 | D-08, D-13, A-06, A-07 | Commit **adds** the time-field value; field is pre-filled with pending time since last commit; pending is provisionally attributed to the current project; today list with editable totals in popup and Reports Day view. | User: "committing time in the time-field should always add to the total" plus a list of today's projects with editable totals. |
| 2026-09-07 | A-01 | Sleep/lock time discarded; tracking auto-pauses. | User confirmed. |
| 2026-09-07 | A-03 | App launches idle and shows the popup. | User confirmed. |
| 2026-09-07 | D-10 | Bare integer = minutes, bare decimal = hours. | User confirmed. |
| 2026-09-07 | D-02 | Minimum target macOS 15; glass via NSVisualEffectView materials. | User confirmed. |
| 2026-09-07 | — | Bundle identifier `com.hypertime.app`, display name "Hypertime". | User: go with default. |
| 2026-09-07 | D-14 | Passive popup auto-hides after 20 s (setting); engagement cancels it; the bucket keeps accumulating. Close also keeps the bucket. | User request. |
| 2026-09-07 | R-04 | Dedicated Discard button (⌘⌫) drops the pending bucket, hides the popup, returns focus; tracking continues. | User request. |
| 2026-09-07 | D-15 | Editing the amount edits the bucket: the committed amount replaces pending; no hidden remainders. | User: "if I change the amount I am adjusting the bucket itself". |
| 2026-09-07 | D-12 | CSV defaults: comma delimiter, full stop decimal separator. | User confirmed. |
