# Parent update drafts

## Purpose and non-delivery guarantee

Parent updates are staff-only drafting artifacts. The lifecycle is:

```text
generated -> edited -> reviewed -> approved
                      \-> rejected
any non-archived state -> archived
```

“Approved” means eligible for a future separately authorized delivery phase. There is no recipient, delivery, chat, notification, email, SMS, or APNs operation in Phase 11C–11E. Parents and players have no RLS read policy or navigation entry.

## Safe content

Sections are recent work, positive developments, current focus, consistency, recent testing, evidence limitations, and upcoming next steps. The generator uses a parent-safe projection of Phase 11A evidence and deterministic trends.

Excluded content includes private coach notes, internal comments/alert labels, confidential comparisons, other players, recruiting guarantees, financial information, medical conclusions, raw device/GPS/file data, and private storage references. Daily-log counts are described without treating absent logs as missed work.

## Audit history

The draft stores the generated original and current coach-edited content independently. Append-only review events preserve generated, edited, reviewed, approved, rejected, and archived transitions with actor, timestamp, safe note, and content snapshot. Approval/rejection/archive identities and timestamps remain queryable. Historical records are never hard deleted by lifecycle functions.

## Authorization

Every create/list/detail/edit/review/approve/reject/archive action verifies active organization staff and the existing player scope. The service-role RPC repeats transferred-actor authorization. Direct authenticated writes are revoked.
