# Paste-ready prompt for Claude Cowork

```
I'm shipping an iPhone app called Vocabi (vocabulary widgets + quiz + global leaderboard + "Vocabi Pro" subscription with AI word packs). The code is finished and pushed to github.com/alpsenell/vocabi. I need you to drive the remaining account-side release steps with me. Everything you need is in the repo:

- docs/HANDOFF_COWORK.md — the step-by-step runbook (steps 1–10). Treat it as the source of truth.
- docs/CLOUDKIT_SETUP.md and docs/cloudkit-schema.ckdb — CloudKit record types and indexes.
- server/README.md — how to deploy the pack server to Cloudflare Workers.
- docs/PRICING.md — subscription products, prices and trial terms.
- docs/appstore/ — metadata in en-US / tr / fr-FR / es-ES, privacy policy, review notes, naming research.
- Scripts/screenshots/ — screenshot capture and framing scripts.

Already done, do not redo: signing team set in project.yml; privacy policy hosted at https://alpsenell.github.io/vocabi/privacy; vocabulary content review applied; nickname profanity filter and "Report nickname" action implemented in code; an archive builds successfully.

Please work through these in order, asking me to sign in or confirm where needed, and keep a running checklist with status (done / blocked / needs me):

1. Apple Developer portal: register iCloud container iCloud.com.alpsenel.wordwidget; enable iCloud (CloudKit) + App Groups (group.com.alpsenel.wordwidget) on App IDs com.alpsenel.wordwidget and com.alpsenel.wordwidget.widget. (Handoff step 1)
2. CloudKit Dashboard: import docs/cloudkit-schema.ckdb into Development (record types PeriodScore and NicknameReport with the indexes and security roles described in docs/CLOUDKIT_SETUP.md), then Deploy Schema Changes to Production. (Step 2)
3. Cloudflare: deploy the pack server from server/ following server/README.md — wrangler login, create the PACKS KV namespace and paste its id into wrangler.toml, set secrets ANTHROPIC_API_KEY and DEV_BYPASS_TOKEN, npm run deploy, upgrade to the Workers Paid plan, run the health and one pack curl test. Tell me the final worker URL; if it is not https://vocabi-packs.alpsenel.workers.dev, flag it so engineering can update App/Sources/Shared/AppInfo.swift. (Step 9)
4. App Store Connect: create the app record (name "Vocabi: Words on Your Widgets", fallback "Vocabi – Widget Vocabulary" if rejected; bundle ID com.alpsenel.wordwidget; SKU vocabi-ios), add tr / fr-FR / es-ES localizations from docs/appstore/metadata, categories Education + Reference, age 4+, free with in-app purchases. (Step 4)
5. Subscriptions: accept Paid Apps agreement and complete tax/banking; create subscription group "Vocabi Pro" with com.alpsenel.wordwidget.pro.monthly ($9.99 / 1 month) and com.alpsenel.wordwidget.pro.weekly ($2.99 / 1 week), each with a 3-day free trial introductory offer for all territories; localized names/descriptions in the four languages; consider the Small Business Program. (Step 10)
6. App Privacy: answer the questionnaire per handoff steps 4 and 10 (Other User Content: nickname; Gameplay Content: scores; Purchases; Identifiers: anonymous install id; nothing used for tracking). Set the privacy policy URL above and make sure the hosted policy text mentions the pack server (language pair, level, topic, anonymous install id, signed subscription receipt; no personal data) — if it doesn't, update docs/appstore/PRIVACY_POLICY.md and republish the gh-pages site.
7. App Review Information: paste docs/appstore/REVIEW_NOTES.md including the UGC moderation paragraph; note that the leaderboard needs iCloud and that a reviewer can test Pro with the sandbox trial.
8. Screenshots: on an iPhone 17 Pro Max simulator, add two or three Vocabi widgets to the home screen by hand with different "Widget slot" values, run Scripts/screenshots/capture.sh for en, tr, fr, es (INTERACTIVE=1 lets you take the widget shot manually), then Scripts/screenshots/compose.py, and upload six framed images per locale to the 6.9" set. (Step 5)
9. TestFlight: archive and upload from Xcode (scheme WidgetApp), add me as an internal tester, and give me a device checklist: widgets appear in the gallery, different slots show different words, tap mode advances, quiz runs, leaderboard shows a score after iCloud sign-in, Report nickname works, paywall shows real sandbox prices, trial starts, Settings shows Pro, AI packs download, cancellation returns the app to Free. (Steps 8 and 10.7)
10. Submit for review once 1–9 are green and report anything Apple rejects verbatim.

When you finish, send me: the checklist, the worker URL, any price tiers or names Apple changed, and a list of items that need an engineering change.
```
