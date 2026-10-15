# Vocabi — Product & Architecture Spec

Vocabi is an iPhone app (iOS 17+) that teaches vocabulary through home-screen widgets and an in-app quiz with a global leaderboard.

## Product rules (source of truth)

1. **Widget** shows the *word* (target language) on top and its *description* (native language) below. Medium and small families; large shows an example sentence too.
2. **Refresh frequency** is a global setting: `hourly`, `daily`, `weekly`, `onTap`. In `onTap` mode the widget is interactive: tapping advances to the next word without opening the app.
3. **Multiple widgets never show the same word at the same time.** Each widget instance is configured with a *slot* (1…6, default 1) via `AppIntentConfiguration`. `WordScheduler` guarantees distinct words across slots.
4. **Languages**: English, Turkish, French, Spanish. User picks a *native* language and a *target* language (must differ). Word = target, description = native.
5. **Difficulty**: beginner / intermediate / advanced (multi-select). **Categories**: business, school, dailyLife, travel, technology, health, food (multi-select).
6. **Quiz** in the main app uses words the user has *seen* in widgets (shared `seenEntryIds`); pads from the pool when fewer than 10 are seen. 10 multiple-choice questions, score = correct×100 + speed bonus (max 50/question).
7. **Leaderboard**: global daily / weekly / monthly, CloudKit public database, nickname only.
8. **App Store**: name "Vocabi" (full title decided by branding teammate, must be distinctive), original icon and screenshots, metadata in en/tr/fr/es.

## Architecture

```
Packages/VocabCore           ← Swift package shared by app + widget (models, store, scheduler, repository, quiz engine)
App/Sources                  ← SwiftUI app target "WidgetApp" (bundle com.alpsenel.wordwidget, display name Vocabi)
Widget/Sources               ← WidgetKit extension "WidgetAppWidget" (bundle com.alpsenel.wordwidget.widget)
App/Resources, Widget/Resources ← asset catalogs, vocabulary JSON lives in VocabCore resources
docs/                        ← this spec, App Store metadata
```

* App Group: `group.com.alpsenel.wordwidget`. All shared state goes through `SharedStore` (VocabCore). Never touch `UserDefaults.standard` for shared state.
* iCloud container: `iCloud.com.alpsenel.wordwidget`.
* Deep link scheme: `vocabi://word/<entryId>`, `vocabi://quiz`.
* Widget kind string: `"VocabiWordWidget"`. Reload after any settings change with `WidgetCenter.shared.reloadAllTimelines()`.
* Project is generated with **xcodegen** from `project.yml`. Sources are folder-based: adding a file under the right folder is enough. **Only the lead edits `project.yml`.**

## Vocabulary data format

`Packages/VocabCore/Sources/VocabCore/Resources/vocabulary.json` — array of `VocabEntry`:

```json
{
  "id": "business-0001",
  "category": "business",
  "difficulty": "intermediate",
  "terms":       { "en": "invoice", "tr": "fatura", "fr": "facture", "es": "factura" },
  "definitions": { "en": "A document listing goods or services provided and the amount owed.",
                   "tr": "Sağlanan mal veya hizmetleri ve ödenecek tutarı listeleyen belge.",
                   "fr": "Document listant les biens ou services fournis et le montant dû.",
                   "es": "Documento que enumera los bienes o servicios prestados y el importe adeudado." },
  "examples":    { "en": "Please pay the invoice within 30 days.", "tr": "...", "fr": "...", "es": "..." }
}
```

Every entry must have all four languages for `terms` and `definitions`; `examples` optional but preferred. Target ≥ 100 entries per category (≈ 700 total), balanced across difficulties.

## Build & run conventions for teammates

```
cd /Users/alp/Desktop/Personal-Projects/WidgetApp
xcodegen generate                                   # regenerates WidgetApp.xcodeproj (gitignored)
xcodebuild -project WidgetApp.xcodeproj -scheme WidgetApp \
  -destination 'platform=iOS Simulator,name=<YOUR ASSIGNED SIMULATOR>' \
  -derivedDataPath /tmp/dd-<yourname> build
swift test --package-path Packages/VocabCore        # core unit tests (macOS host)
```

Each teammate uses only the simulator assigned in their brief and `xcrun simctl shutdown <udid>` when finished. **Never build with `CODE_SIGNING_ALLOWED=NO`**: it strips the iCloud/App Group entitlements from the simulator binary and CloudKit then traps at runtime. Default ad-hoc simulator signing embeds them.
