# Vocabi — App Store naming research

Checked on 2026-10-15 using web search and the public iTunes Search API
(`https://itunes.apple.com/search?term=<term>&entity=software&country=<cc>`), storefronts us, tr, fr, es, gb.

## Decision

| Field | Value | Length |
|---|---|---|
| **App Store name (en-US)** | `Vocabi: Words on Your Widgets` | 29 / 30 |
| **Subtitle (en-US)** | `Glance. Learn. Quiz. Compete.` | 29 / 30 |
| Home-screen display name | `Vocabi` (`CFBundleDisplayName`, unchanged) | — |

Localized names (they all start with "Vocabi" so the brand reads the same everywhere):

| Locale | Name | Subtitle |
|---|---|---|
| en-US | Vocabi: Words on Your Widgets | Glance. Learn. Quiz. Compete. |
| tr | Vocabi: Ana Ekranda Kelimeler | Bak, öğren, test et, yarış |
| fr-FR | Vocabi : des mots en widgets | Un coup d'œil, un mot de plus |
| es-ES | Vocabi: palabras en widgets | Mira, aprende, juega y compite |

### Why not plain "Vocabi"
**An app named exactly "Vocabi" already exists** (developer Richard Della, an English vocabulary app with a word library, flashcards and quizzes). It shows up in every storefront we checked. App Store Connect won't accept a name that another app already uses, and users would mix the two up anyway, so the name needs a suffix.

### Why this suffix
- The widget category is crowded with names built from the same parts: "Vocab Widget" (two apps), "Word Widget: Daily Vocabulary", "English Word Widget", "Widget Vocabulary", "Widget Voca", "Word of the Day: Widget", "Word of The Day Widget: Voca", "LinguistWidget: Daily Word", "Kotoba – Your Words Widget". The suffix "Words on Your Widgets" still includes the search terms *words* and *widgets*, but it is a phrase rather than another "X Widget" label. No app in the search results uses it.
- It describes the product (words go on your own home-screen widgets, and there can be several). It also leaves the subtitle free for the quiz and leaderboard.
- Search for the exact phrase "Words on Your Widgets": no matching app was found.

## Findings

### Exact / near-exact "Vocabi" matches
| App | Developer | URL |
|---|---|---|
| **Vocabi** (exact collision) | Richard Della | https://apps.apple.com/us/app/vocabi/id6446959819 (also /si/, /tr/, /fr/, /es/, /gb/) |
| Vocabie: Learn Vocabulary | Jakub Hyl | https://apps.apple.com/us/app/vocabie-learn-vocabulary/id6797068153 |
| Vocabie: Vocabulary Flashcards | Cengiz Kuscu | (tr/fr/es storefronts) |
| Vocaby - Vocabulary Builder | Pacifiq | https://apps.apple.com/us/app/vocaby-vocabulary-builder/id6767075692 |
| Vocabian: Words & Grammar | Yigit Kandemir | https://apps.apple.com/us/app/vocabian-words-grammar/id6812243107 |
| Vocabuo - Language Vocabulary | Vocabuo s.r.o. | https://apps.apple.com/us/app/vocabuo-language-vocabulary/id6462440027 |
| Vocabin - Learn Words & Save | — | https://apps.apple.com/us/app/-/id6749776346 |
| Vocabia (Vocabulary Builder: Vocabia) | — | https://apps.apple.com/us/app/vocabulary-builder-vocabia/id6744903257 |
| Vocabi (not on the App Store: AI web tool / browser extension) | — | https://aiindigo.com/tool/vocabi, https://www.producthunt.com/p/vocabi |

### "Vocabli"
| App | Developer | URL |
|---|---|---|
| Vocabli. Learn New Words Daily | Siddhesh Shirke | https://apps.apple.com/us/app/vocabli-learn-new-words-daily/id6745424324 |
| Vocabli | Ming Kang Siow | https://apps.apple.com/us/app/vocabli/id6806206722 |
| Vocably (several apps) | various | e.g. https://apps.apple.com/us/app/vocably-dictionary-flashcards/id1641258757 |

### "Vocabu"
| App | Developer | URL |
|---|---|---|
| Vocabu - Improve Your English vocabulary | Sergey Rozovik | https://apps.apple.com/us/app/vocabu-improve-your-english-vocabulary/id947384234 |
| Vocabulary Flashcards - Vocabu | Daniel Reicher | https://apps.apple.com/us/app/vocabulary-flashcards-vocabu/id1392547708 |
| Vocabu – English Vocabulary | Lilla Kato | https://apps.apple.com/us/app/vocabu-english-vocabulary/id6761463414 |

### "vocab widget" / "word widget"
| App | URL |
|---|---|
| Vocab Widget (Jaden Scali) | https://apps.apple.com/us/app/vocab-widget/id6452119871 |
| Vocab Widget - Learn New Words (Daniel Ni) | https://apps.apple.com/us/app/vocab-widget-learn-new-words/id6763810717 |
| Word Widget: Daily Vocabulary | https://apps.apple.com/us/app/word-widget-daily-vocabulary/id6446258258 |
| English Word Widget | https://apps.apple.com/us/app/english-word-widget/id1554536747 |
| Widget Vocabulary: Learn Words | https://apps.apple.com/us/app/widget-vocabulary-learn-words/id6775767149 |
| Widget Voca | https://apps.apple.com/us/app/widget-voca/id6742835098 |
| Word of the Day: Widget | https://apps.apple.com/us/app/word-of-the-day-widget/id1536210624 |
| Word of The Day Widget: Voca | https://apps.apple.com/us/app/word-of-the-day-widget-voca/id6739798854 |
| LinguistWidget: Daily Word | https://apps.apple.com/us/app/linguistwidget-daily-word/id6758740879 |
| Vocabito: Spanish Word Widget | https://apps.apple.com/us/app/vocabito-spanish-word-widget/id6759367008 |
| Bloo: Daily Language Widget | https://apps.apple.com/app/id6757953587 |
| Learn on Widgets | https://apps.apple.com/gr/app/learn-on-widgets/id6664071230 |
| Vocabulary - Learn words daily (Monkey Taps) | https://apps.apple.com/us/app/vocabulary-learn-words-daily/id1084540807 |

## Visual differentiation (icon)
The icons in this category are mostly blue, green or orange, with a book, a speech bubble, a mascot or flashcards. Vocabi uses a **deep plum single-hue gradient** with a warm paper widget tile. The tile shows a bold geometric "V" and a short coral line under it (word over description), and a translucent second tile sits behind it to stand for multiple widget slots. See `docs/appstore/icon/`.

## Brand colors
| Token | Hex | Use |
|---|---|---|
| Plum (accent, light) | `#7B2D8E` | AccentColor light, screenshot caption band |
| Plum (accent, dark) | `#D29AE6` | AccentColor dark |
| Plum deep | `#240833` → `#6B2280` | icon background gradient |
| Paper | `#FFF4EA` | icon tile, caption text |
| Coral | `#FF7A6B` | secondary accent ("description" line) |

## Before submission
Re-run the iTunes Search query for the final name. App Store Connect checks for name collisions when you create the app record, and that check is the one that counts.
