# CloudKit setup for the Vocabi leaderboard

The global leaderboard (daily / weekly / monthly) lives in the **public database** of the
container `iCloud.com.alpsenel.wordwidget`. Players are identified only by their iCloud user
record name; the leaderboard shows only the nickname they chose in the app.

The code is in `App/Sources/Leaderboard/CloudKitLeaderboardService.swift`. The pure ranking and
offline-queue logic is in `Packages/VocabCore/Sources/VocabCore/Leaderboard/`.

---

## 1. Apple Developer portal (one-time setup)

1. Go to <https://developer.apple.com/account/resources/identifiers/list/cloudContainer>
   (Certificates, IDs & Profiles → Identifiers → filter **iCloud Containers**).
2. Click **+** → **iCloud Containers** → Description `Vocabi`, Identifier
   `iCloud.com.alpsenel.wordwidget` → Register.
   (Container IDs are permanent and cannot be deleted. Double-check the spelling.)
3. Open the App ID **com.alpsenel.wordwidget** (team `6S7Q8F967Q`):
   - Enable **iCloud** → choose *Include CloudKit support* → **Edit** → tick
     `iCloud.com.alpsenel.wordwidget` → Save.
   - **App Groups** must already include `group.com.alpsenel.wordwidget` (it is used by the widget).
   - **Push Notifications** may be on (the entitlements declare `aps-environment`); the leaderboard does
     not use subscriptions, so this is optional.
4. Xcode → target **WidgetApp** → Signing & Capabilities: with automatic signing the provisioning profile
   is regenerated. Check that the iCloud capability shows **CloudKit** and the container
   `iCloud.com.alpsenel.wordwidget` is ticked (it is declared in `App/WidgetApp.entitlements`).
   The widget extension does **not** need iCloud.

## 2. CloudKit Dashboard: schema (Development environment)

Open <https://icloud.developer.apple.com/dashboard/> → container `iCloud.com.alpsenel.wordwidget`
→ **Development** → **Schema**.

### Record type `PeriodScore`

Record Types → **+** → name `PeriodScore`, then add these fields:

| Field             | Type          | Notes |
|-------------------|---------------|-------|
| `playerId`        | String        | iCloud user record name of the player |
| `nickname`        | String        | display name (trimmed, max 20 chars) |
| `period`          | String        | `daily`, `weekly` or `monthly` |
| `periodKey`       | String        | `2026-10-15`, `2026-W42`, `2026-10` (UTC, ISO weeks) |
| `targetLanguage`  | String        | `en`, `tr`, `fr`, `es` |
| `total`           | Int(64)       | accumulated score for that window |
| `updatedAt`       | Date/Time     | last update |
| `recentResultIds` | String (List) | last 30 applied quiz ids — makes retries idempotent (not indexed) |

The record name is deterministic: `<playerId>|<period>|<periodKey>|<targetLanguage>`,
so each player has at most one record per window and language.

> Alternative: in the Development environment CloudKit creates the record type and fields
> automatically the first time a signed-in device saves a score ("just-in-time schema").
> The **indexes below are never created automatically** — you must add them by hand either way.

### Indexes

Schema → **Indexes** → record type `PeriodScore` → **Add Basic Index** for each line:

| Field            | Index type |
|------------------|------------|
| `recordName`     | QUERYABLE  |
| `playerId`       | QUERYABLE  |
| `period`         | QUERYABLE  |
| `periodKey`      | QUERYABLE  |
| `targetLanguage` | QUERYABLE  |
| `total`          | QUERYABLE  |
| `total`          | SORTABLE   |

Save. Without these, queries fail with *"Field … is not marked queryable/sortable"*
(the app shows the generic error state).

### Security roles

Schema → **Security Roles**. Default public-database permissions are fine:

| Role            | PeriodScore |
|-----------------|-------------|
| `_world`        | Read        |
| `_icloud`       | Create, Read |
| `_creator`      | Read, Write |

Keep `_icloud` **without Write**: only the creator of a record can modify it, so players cannot
change each other's totals.

### Record type `NicknameReport` (Report nickname)

Saved when a player long-presses / swipes a leaderboard row and taps **Report nickname**
(`CloudKitLeaderboardService.reportNickname`). The record name is `<reporterId>|<reportedRecordName>`,
so one player reporting the same row twice creates only one record.

| Field                | Type      | Notes |
|----------------------|-----------|-------|
| `reportedRecordName` | String    | `PeriodScore` record name of the reported row (`<playerId>\|<period>\|<periodKey>\|<lang>`) |
| `reportedNickname`   | String    | nickname as it was displayed |
| `reporterId`         | String    | iCloud user record name of the reporter |
| `createdAt`          | Date/Time | when the report was made |

Indexes (Schema → Indexes → `NicknameReport`): `recordName` QUERYABLE, `reportedRecordName` QUERYABLE,
`createdAt` QUERYABLE and `createdAt` SORTABLE (newest first in the Dashboard).

Security roles: **no world read** — reports are only readable by their creator (and by you in the Dashboard).

| Role       | NicknameReport |
|------------|----------------|
| `_world`   | (none)         |
| `_icloud`  | Create         |
| `_creator` | Read, Write    |

**Moderating:** Dashboard → Data → Public Database → `NicknameReport` → sort by `createdAt`. For an offensive
name, open the `PeriodScore` record(s) named in `reportedRecordName` (same player id prefix for other
periods) and delete them or blank the `nickname` field (the app then shows `Player-XXXX`). Players without
iCloud cannot send reports; the row is still hidden for them locally (App Group key
`leaderboard.reportedRecords.v1`). Nicknames matching the built-in word list
(`Packages/VocabCore/Sources/VocabCore/Resources/blocked-nicknames.txt`) can't be chosen in the app and are
replaced by `Player-XXXX` when displayed.

## 3. Deploy to Production

Before TestFlight / App Store (both use the **Production** environment):

1. CloudKit Dashboard → **Deploy Schema Changes…** → review that `PeriodScore`, `NicknameReport`, all
   fields and all indexes are listed → **Deploy**.
2. Schema changes in Production are additive only (fields/types can't be removed later), so deploy
   once the schema above is final.
3. Data is **not** copied: Development data stays in Development.
4. Debug builds from Xcode use Development; TestFlight and App Store builds use Production
   (the `aps-environment` / `com.apple.developer.icloud-container-environment` is set by the
   distribution profile).

## 4. Testing

- **Simulator:** CloudKit works on the simulator, but the simulator must be signed in to an Apple ID
  (Settings → Sign in to your iPhone) with iCloud Drive enabled. Without it, the leaderboard shows the
  *"Sign in to iCloud in Settings to join the global ranking"* state and quiz scores stay queued locally
  (`leaderboard.pendingResults.v1` in the App Group) until a signed-in launch. Prefer a test Apple ID.
- **Device:** sign in to iCloud; run a Debug build; finish a quiz; check **CloudKit Dashboard → Data →
  Public Database → `PeriodScore`** (query needs the `recordName` QUERYABLE index to list records).
- **Unit tests:** `swift test --package-path Packages/VocabCore` covers period keys (UTC, ISO-week
  edges), ranking/tie rules, the "100+" approximation, the offline queue and retry flow (mock service).
- **Resetting Development data:** Dashboard → container → *Reset Development Environment* (wipes schema
  and data — re-add the indexes afterwards).

## 5. Abuse limits and known trade-offs

- **Client-side validation only.** CloudKit has no server code, so a modified client could write any
  `total` to its own records. Mitigations in the app: scores outside `1…1500` per quiz are dropped
  (`LeaderboardRanking.maxScorePerQuiz`), nicknames are trimmed to 20 characters and control
  characters removed. If cheating becomes a problem: delete offending records in the Dashboard
  (Data → query → delete), or move scoring to a server.
- **Players can only edit their own records** (`_creator` write role), so they cannot lower other
  players' scores.
- **Nicknames are user-generated content.** The app filters nicknames against a word list (en/tr/fr/es)
  on entry and on display, and offers **Report nickname** on other players' rows (see `NicknameReport`
  above). Check reports in the Dashboard regularly. The filter is client-side, so a modified client could
  still write any nickname; the display-side check and reports cover that.
- **Rate limits:** CloudKit returns `requestRateLimited` / `serviceUnavailable` under load; the app
  maps these to a network error and keeps the result queued (max 50 results, dropped after 40 days).
  Each quiz costs 3 fetch + 3 save requests; each leaderboard load costs 1 query + 1 record fetch, plus
  paged id-only queries to count players ahead when you are outside the top 100 (capped at 1000 → "1000+").
- **Free quota:** the public database's free tier scales with active users and is far above what this
  workload needs; check *Dashboard → Usage* after launch.
- **Old data:** records accumulate one per player × window × language. They are small; optionally
  delete records with old `periodKey` values from the Dashboard once a year.
- **Account switch:** the cached player id (`leaderboard.playerId.v1` in the App Group) is cleared
  whenever iCloud becomes unavailable.
- **Privacy:** the iCloud user record name is an opaque, app-scoped id; no name or email is read.
  Mention "nickname and score are shown publicly" in the privacy policy / App Privacy answers
  (*User Content → Gameplay Content*, not linked to identity, not used for tracking).
