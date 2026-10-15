# Vocabi — Handoff for Claude Cowork: manual release steps

**Context for the assistant reading this:** Vocabi is an iPhone app (iOS 17+, SwiftUI, WidgetKit, CloudKit) that teaches vocabulary through home-screen widgets and an in-app quiz with a global leaderboard. The code is complete, builds, and all unit tests pass. The remaining work needs the developer's Apple account, browser access, and human judgement. Repository: `github.com/alpsenell/vocabi` (folder `docs/` holds every reference file named below). Please work through the steps in order, ask me to sign in where needed, and report back what is done and what is blocked.

## Fixed identifiers (do not change)

| Item | Value |
|---|---|
| App bundle ID | `com.alpsenel.wordwidget` |
| Widget bundle ID | `com.alpsenel.wordwidget.widget` |
| App Group | `group.com.alpsenel.wordwidget` |
| iCloud container | `iCloud.com.alpsenel.wordwidget` |
| Apple Team ID | `UTZLUFML6U` |
| Home-screen name | Vocabi |
| App Store title (en-US) | Vocabi: Words on Your Widgets |
| App Store subtitle (en-US) | Glance. Learn. Quiz. Compete. |
| Localized titles | tr: "Vocabi: Ana Ekranda Kelimeler" · fr-FR: "Vocabi : des mots en widgets" · es-ES: "Vocabi: palabras en widgets" |
| Version / build | 1.0.0 / 1 |

## Step 1 — Apple Developer portal

1. Go to developer.apple.com → Certificates, Identifiers & Profiles → Identifiers.
2. Under **iCloud Containers**, register `iCloud.com.alpsenel.wordwidget` (description: "Vocabi leaderboard").
3. Open the App ID `com.alpsenel.wordwidget` (create it if missing, "Vocabi"). Enable **iCloud** with CloudKit and tick the container above. Confirm **App Groups** is enabled with `group.com.alpsenel.wordwidget`. Enable **Push Notifications** only if asked by Xcode (the entitlement is present but unused).
4. Do the same App Group for the widget App ID `com.alpsenel.wordwidget.widget`.
5. In Xcode (Signing & Capabilities, both targets), confirm the container and group show as ticked with no red warnings.

## Step 2 — CloudKit Dashboard schema (Development, then Production)

Open icloud.developer.apple.com/dashboard, container `iCloud.com.alpsenel.wordwidget`, **Development** environment, Schema → Record Types. Create record type **`PeriodScore`** with these fields:

| Field | Type |
|---|---|
| `playerId` | String |
| `nickname` | String |
| `period` | String |
| `periodKey` | String |
| `targetLanguage` | String |
| `total` | Int(64) |
| `updatedAt` | Date/Time |
| `recentResultIds` | String (List) |

Indexes to add (Schema → Indexes):

| Field | Index |
|---|---|
| `recordName` | QUERYABLE |
| `playerId` | QUERYABLE |
| `period` | QUERYABLE |
| `periodKey` | QUERYABLE |
| `targetLanguage` | QUERYABLE |
| `total` | QUERYABLE and SORTABLE |

Security roles (Schema → Security Roles): keep defaults so `_icloud` (any signed-in user) can **create and read**, and `_creator` can **write** their own records. World should be read-only or none.

Then **Deploy Schema Changes to Production**. Full explanation and testing notes are in `docs/CLOUDKIT_SETUP.md`.

## Step 3 — Privacy policy hosting

1. The policy text is in `docs/appstore/PRIVACY_POLICY.md`. Replace the placeholder contact `support@EXAMPLE.com` with a real address.
2. Host it at a public URL. Suggested: a GitHub Pages site so it resolves at `https://alpsenel.github.io/vocabi/privacy` (that exact URL is what the app currently links to in `App/Sources/Shared/AppInfo.swift`). If you host elsewhere, tell me the final URL so the app constant can be updated.
3. The same URL goes into App Store Connect → App Privacy → Privacy Policy URL.

## Step 4 — App Store Connect record

1. appstoreconnect.apple.com → My Apps → New App: platform iOS, name **Vocabi: Words on Your Widgets**, primary language English (U.S.), bundle ID `com.alpsenel.wordwidget`, SKU `vocabi-ios`. If the name is rejected as taken, try "Vocabi – Widget Vocabulary" and tell me which one was accepted.
2. Add localizations Turkish, French, Spanish (Spain). For each locale copy the texts from `docs/appstore/metadata/<locale>/` (name, subtitle, description, keywords, promotional_text, release_notes).
3. Category: Education; secondary: Reference. Age rating: 4+. Price: free.
4. App Privacy questionnaire: data collected = **Other User Content** (nickname) and **Gameplay Content** (quiz scores), linked to the user, used for App Functionality, not used for tracking. No third-party SDKs.
5. App Review notes: paste `docs/appstore/REVIEW_NOTES.md`. Mention that the leaderboard requires an iCloud account.
6. Export compliance: the app uses no non-exempt encryption (`ITSAppUsesNonExemptEncryption` is already false).

## Step 5 — Screenshots

Needs a Mac with Xcode 26 and the repo cloned.

1. Build and install on a 6.9" simulator (iPhone 17 Pro Max). Add two or three Vocabi widgets to the home screen by hand (long-press → Edit → Add Widget), and set a different **Widget slot** on each (long-press the widget → Edit Widget).
2. Run `Scripts/screenshots/capture.sh <simulator-udid> <locale>` for `en`, `tr`, `fr`, `es`; with `INTERACTIVE=1` it pauses before each shot so the home screen with widgets can be captured manually.
3. Run `python3 Scripts/screenshots/compose.py` to produce framed 1290×2796 images in `Scripts/screenshots/out/<locale>/`. Captions are in `captions.json`.
4. Upload 6 per locale to App Store Connect (6.9" display set; the 6.5" set can reuse them).

## Step 6 — Content review by native speakers

Ask a native speaker to check these dataset terms in `Packages/VocabCore/Sources/VocabCore/Resources/vocabulary.json` (search by the English term):

- Turkish: errand ("ayak işi"), in-laws ("kayınlar"), well-being ("esenlik"), abstract ("özet bildiri"), lecture ("ders anlatımı"), assignment ("görev ödevi"), remission ("hastalığın gerilemesi"), degree ("akademik derece").
- Spanish: elective ("asignatura optativa"), small talk ("charla trivial"), upgrade ("ascenso de categoría"), phishing ("suplantación de identidad").
- French: lecturer ("maître de conférences"), overbooked ("en surréservation"), branch ("succursale" vs "agence").
- Level placement to reconsider: calorie, crispy, expiration date (tagged advanced, probably intermediate).
- English spelling: terms use US spelling; a few example sentences use British spelling. Decide one convention.

Report corrections as a list of `id → field → new text` so they can be applied to the JSON.

## Step 7 — User-generated content safeguards (App Review requirement)

The leaderboard shows user-chosen nicknames. Before submission decide one of:

- (a) Add a profanity filter list for nicknames and a "Report nickname" action in the leaderboard, or
- (b) Document in review notes that nicknames are sanitized (trimmed, 3–20 chars) and that the developer can delete offending records from CloudKit Dashboard.

Option (a) is safer for approval. If chosen, note it as an engineering task to pass back.

## Step 8 — TestFlight

1. In Xcode, Product → Archive with the `WidgetApp` scheme, then Distribute → App Store Connect → Upload.
2. Add internal testers, verify on a real device: widgets appear in the gallery, different slots show different words, tap mode advances, quiz runs, leaderboard shows a score after signing in to iCloud.
3. Report any crash logs from TestFlight back to engineering.

## Deliverables to send back

- Confirmation of each step above with any accepted/rejected names or URLs.
- The final privacy policy URL.
- The native-speaker corrections list.
- The decision on nickname moderation.
- Links to screenshots uploaded or the folder of composed images.
