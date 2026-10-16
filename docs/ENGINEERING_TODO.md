# Engineering tasks before App Store submission

## 1. Nickname moderation (App Review UGC requirement) — decided: option (a)

Decision (15 Oct 2026): ship a profanity filter plus a "Report nickname" action rather than relying on review-notes wording alone.

- [x] Add a profanity word list (en, tr, fr, es) to `VocabCore`, e.g. `Packages/VocabCore/Sources/VocabCore/Resources/blocked-nicknames.txt`.
- [x] In `App/Sources/Shared/Nickname.swift`, reject a nickname when, after lower-casing and stripping diacritics/digits-for-letters (0→o, 1→i, 3→e, 4→a, 5→s), it contains a blocked term. Show the existing validation error state.
- [x] Leaderboard rows: add a context-menu / swipe action **Report nickname**. On tap, save a `NicknameReport` record to the CloudKit public database: `reportedRecordName` (String), `reportedNickname` (String), `reporterId` (String), `createdAt` (Date). Add the record type to `docs/cloudkit-schema.ckdb`, import it to Development and deploy to Production again.
  - [ ] **Owner:** import `docs/cloudkit-schema.ckdb` to Development (or create `NicknameReport` by hand per `docs/CLOUDKIT_SETUP.md`), add the indexes, then deploy to Production.
- [x] Optionally hide the reported row locally for the reporter (persist reported record names in the App Group).
- [ ] Once shipped, paste the UGC paragraph from `docs/appstore/REVIEW_NOTES.md` into App Store Connect → App Review Information → Notes.

## 2. Signing team

The Apple Developer account has a single team, `6S7Q8F967Q`. `project.yml` is updated; regenerate the Xcode project (`xcodegen generate`) or set the team in Signing & Capabilities for both targets.

## 3. Privacy policy URL

Hosted from the `gh-pages` branch at https://alpsenell.github.io/vocabi/privacy (note: GitHub user is `alpsenell`, with two l's). `AppInfo.privacyPolicyURL` is updated. To republish after editing `docs/appstore/PRIVACY_POLICY.md`, regenerate `privacy/index.html` on `gh-pages` (pandoc -f gfm -t html5) and push.
