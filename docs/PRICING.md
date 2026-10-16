# Vocabi Pro — pricing and unit economics

Decided 2026-10-16. Product IDs and prices below are the contract for the app, the StoreKit test configuration, App Store Connect and the pack server.

## Tiers

| | Free | Vocabi Pro |
|---|---|---|
| Bundled 701-word library, all 4 languages | ✓ | ✓ |
| Widgets, slots, all refresh modes | ✓ | ✓ |
| Quiz + global leaderboard | ✓ | ✓ |
| AI word packs (fresh words per level and category, refreshed continuously) | – | ✓ |
| Custom topics you type ("sailing", "job interviews"), up to 5 | – | ✓ |
| Unlimited vocabulary | – | ✓ |

The free tier keeps the widget useful forever, which protects App Store ratings and review. Pro is the "more and personal" upgrade.

## Products (App Store Connect subscription group "Vocabi Pro")

| Product ID | Period | Price (US) | Intro offer |
|---|---|---|---|
| `com.alpsenel.wordwidget.pro.weekly` | 1 week | **$2.99** | 3-day free trial |
| `com.alpsenel.wordwidget.pro.monthly` | 1 month | **$9.99** | 3-day free trial |

Monthly is 16% cheaper than four weeks of weekly ($11.96), which is the "slightly cheaper" anchor requested. The paywall shows monthly as the highlighted default with the saving badge, weekly as the low-commitment option.

Optional later: `com.alpsenel.wordwidget.pro.yearly` at $49.99 (58% off monthly). Annual plans usually produce the most revenue per install; add it once conversion data exists.

Use App Store Connect price tiers so local prices round naturally (e.g. ₺ and € equivalents are chosen by Apple's grid).

## Cost model (what one subscriber costs us)

Assumptions: Claude Opus 5.5 at $4 / $20 per million input / output tokens; a pack is 40 entries ≈ 1.2K input tokens (prompt + schema) and ≈ 6K output tokens including brief thinking.

| Item | Cost |
|---|---|
| One generated pack (40 words, Opus 5.5) | ≈ $0.13 |
| Same pack with Haiku 5.5 (used only for the verification pass) | ≈ $0.004 |
| Pre-generating the standard catalogue: 12 language pairs × 3 levels × 7 categories × 2 pages = 504 packs | ≈ $65 one-time, refreshed quarterly |
| A subscriber's custom topics: 5 topics × 2 pages, uncached | ≈ $1.30 one-time |
| Heavy user top-ups (hourly widget, 6 slots ≈ 4,300 words/month, mostly cache hits) | ≈ $0.30–0.60 / month |
| Cloudflare Workers paid plan (recommended for CPU time) | $5 / month flat |

Standard-category packs are shared by every user through the server cache, so the marginal cost is driven almost entirely by custom topics. **Expected cost per paying user: about $0.50 / month in steady state, worst case about $2 in the first month** for a user who adds five topics on day one.

## Margin

| Plan | Gross | Apple 15% (Small Business Program) | Net | Cost | Margin |
|---|---|---|---|---|---|
| Weekly ×4 | $11.96 | $1.79 | $10.17 | $0.50 | ≈ 95% |
| Monthly | $9.99 | $1.50 | $8.49 | $0.50 | ≈ 94% |

At Apple's standard 30% the margins stay above 90%. The pricing is therefore set by market position, not cost: widget utilities charge $1.99–4.99 per month, language apps $12.99–14.95. Vocabi Pro at $9.99 sits between, justified by generative content and custom topics. If trial-to-paid conversion is below ~3% after launch, test $1.99 weekly / $6.99 monthly before touching features.

## Guardrails that keep cost bounded

- Server cache keyed by (native, target, level, category or topic, page); standard packs pre-generated on a cron.
- Custom topics capped at 5 per user, 2 pages per topic per week, enforced server-side per install id.
- The server only serves packs to a valid StoreKit 2 signed transaction for the two product IDs.
- Packs are stored on device, so a lapsed subscriber keeps what they downloaded but gets nothing new.
