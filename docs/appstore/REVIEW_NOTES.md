# App Review notes: Vocabi 1.0.0

Paste the section below into App Store Connect → App Review Information → Notes.

---

Thank you for reviewing Vocabi. Vocabi mainly works as a home-screen widget, and the app is used for settings and a quiz. No login or demo account is needed.

**1. Pick languages (first launch)**
Open Vocabi. Choose a native language and a target language (they must be different), then levels and topics. You can change these later in Settings.

**2. Add the widget**
1. Go to the Home Screen and long-press an empty area until the icons jiggle.
2. Tap **Edit** (top-left) → **Add Widget**, search for **Vocabi**.
3. Choose the small, medium or large size and tap **Add Widget**.
The widget shows a word in the target language on top and its meaning in the native language below. The large size also shows an example sentence.

**3. Multiple widgets show different words**
Add a second Vocabi widget, long-press it → **Edit Widget**, and set **Widget slot** to *Slot 2*. The two widgets always show different words.

**4. Refresh frequency / tap mode**
In the app's **Settings** tab, change the refresh frequency to Hourly, Daily, Weekly or **On Tap**. With On Tap selected, tapping **Tap for next** on the widget shows the next word without opening the app. This is the quickest way to check the widget during review.

**5. Quiz**
Open the **Quiz** tab and tap **Start quiz**. The quiz has 10 multiple-choice questions built from words the widgets have shown. If fewer than 10 words have been seen, it adds more from the word list, so the quiz works on a fresh install.

**6. Global leaderboard (needs iCloud)**
The leaderboard uses the CloudKit **public database**. To post a score, the device must be **signed in to iCloud**. The nickname (3–20 characters) is set in the app. When a quiz ends, the score is posted, and you can see it in the **Leaderboard** tab (Daily / Weekly / Monthly). If the device isn't signed in to iCloud, the app shows an **iCloud required** message, and the widgets and quiz keep working.

**User-generated content (nicknames):** nicknames are the only user-generated content. They are trimmed to 3–20 characters, filtered against a profanity list before they can be saved, and every leaderboard row has a **Report nickname** action. Reported and offending entries are removed by the developer from the CloudKit Dashboard. _(Paste this paragraph only once the profanity filter + Report action are shipped — see docs/ENGINEERING_TODO.md.)_

**Privacy:** no ads, no tracking, no third-party SDKs. The only data stored off the device is the nickname and quiz scores that the user chooses to post (iCloud public database).

Deep links used by the widget: `vocabi://word/<id>`, `vocabi://quiz`.

---

Contact: alpsenel@outlook.com
