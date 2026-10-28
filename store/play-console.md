# Play Console answers

This is the author's checklist for the Play Console of **Chess Roguelike** (`io.github.orasz.chessroguelike`).
Follow it top to bottom and tick each box. Building and uploading the bundle is in
[`docs/release.md`](../docs/release.md); this file is only what is typed or chosen in the console.

How to read it:

- **Sources.** Every answer comes from what the build does today (see `README.md`, `PRIVACY.md`,
  `CREDITS.md`, and decisions 0002 and 0003 in `docs/decisions/`), and from Play's rules as researched in
  [`docs/research/2026-10-28-open-beta-release.md`](../docs/research/2026-10-28-open-beta-release.md) (§1.4 to
  §1.7). If the game changes, an answer here may stop being true: re-read it before the next release.
- **The console's own wording.** The console's questions, their order and their labels change, and this file was
  written without seeing them. The sections follow the order of the plan, not necessarily the console's. Where an
  item says **check the exact wording in the console**, the question below is a paraphrase: answer what the
  console asks, truthfully, by the facts in this file.
- **`TODO-AUTHOR`** marks the two things only the author knows. Nothing else in this file is left open.

## Facts about the build, as the console sees them

| Fact | Value |
|---|---|
| Name | Chess Roguelike |
| Application id | `io.github.orasz.chessroguelike` |
| Version | 0.1.0, `versionCode` 1 |
| Price | Free, no purchases, no ads |
| Account or login | None |
| Permissions | None declared (the app has no network access either) |
| Data collected or shared | None |
| Audience | 18 and over, for the beta |
| Languages | English (default, `en-US`) and Italian (`it-IT`) |
| Source code | <https://github.com/Orasz/chess-roguelike> (GPLv3) |
| Privacy policy | <https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md> |
| Devices | `arm64-v8a` only: 32-bit-only phones will not see the app (the console's device catalogue shows the count) |

## 1. Privacy policy

- [ ] **App content, Privacy policy:** `https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md`

The page is a public web page that needs no login, and the app links to the same URL from its About screen. Open
it in a private window before saving, to check that it loads.

## 2. App access

- [ ] **All functionality is available without special access.** Choose "All functionality in my app is available
  without any access restrictions" (check the exact wording in the console). No login, no instructions, no test
  account: there is nothing to enter.

## 3. Ads

- [ ] **Does your app contain ads?** No.

## 4. Content rating

- [ ] Start the questionnaire (IARC) from App content, Content rating. Enter the contact email the console asks
  for (the same one as in section 12).
- [ ] **Category:** Game (check the exact wording in the console: the questionnaire offers a small list of app
  types, and a chess game is a game).
- [ ] **Answers.** Answer each question as the questionnaire asks it. The facts, which fix the answers:

| Topic | Answer | Why |
|---|---|---|
| Violence of any kind | No | The fights are chess positions. A piece "captures" another only in the abstract: there is no blood, no injury and no depiction of harm. The player loses HP on a mistake, and an enemy "escapes" or "withdraws" |
| Fear or horror | No | The enemies are pixel-art portraits (a raccoon, a bear, a one-eyed demon) with no scary scene |
| Sexual content or nudity | No | None |
| Profanity or crude humour | No | None |
| Controlled substances (drugs, alcohol, tobacco) | No | The "potion" is a healing item in the game, with no real substance |
| Gambling or simulated gambling | No | No betting, no loot boxes, no random purchase of any kind |
| Users can interact or exchange content | No | The game is single-player, offline, with no chat and no user-generated content |
| Shares the user's location | No | The app does not ask for or use the location |
| Digital purchases | No | There are no purchases |
| Access to the web | Check the exact wording in the console | The About screen has three fixed links (the source code, the privacy policy and the feedback page) that open the phone's browser. The app itself has no network access and no browser inside it. Answer by the questionnaire's own definition |

- [ ] **The rating the console computes is the source of truth.** Do not change an honest answer to get a
  different rating. If the result looks wrong, re-read the question it came from.

## 5. Target audience and content

- [ ] **Target age groups:** tick **18 and over** only, and nothing else.
  - Why: it is the builder's call for the beta, and it is the only choice that is unambiguously outside the
    Families program (the console does not say whether 13-15 or 16-17 pulls an app in). Revisit it for production.
- [ ] **Store presence, appeal to children** (the console asks this for an app whose art could attract
  children; check the exact wording in the console): answer **No**. The game is meant for adult chess players and the
  store art is plain pixel art with no child-oriented characters. If the question's own definition of "appeals to
  children" fits the art better than this file assumes, answer by it, truthfully.
- [ ] **Restrict Minor Access** (18+ only, optional; check the exact wording in the console). It blocks
  Google-determined minors from finding or installing the app. It matches the audience, but it is not required:
  the author decides.

## 6. News app

- [ ] **Is your app a news app?** No.

## 7. COVID-19 contact tracing and status apps

- [ ] Choose "My app is not a publicly available COVID-19 contact tracing or status app" (check the exact
  wording in the console; Google may have retired this declaration, in which case there is nothing to answer).

## 8. Data safety

- [ ] **Does your app collect or share any of the required user data types?** **No.**
  - "Collect" means sending data off the device. The app sends nothing: it has no network access, no analytics,
    no ads and no SDK. The run is saved in a file in the app's private storage, which never leaves the phone.
  - Crash reports in Android vitals are collected by Google, not by the app, and the app contains no code of its
    own for them. They are described in the privacy policy, under "Google Play".
- [ ] **Privacy policy URL:** `https://github.com/Orasz/chess-roguelike/blob/main/PRIVACY.md`
- [ ] **Data deletion:** nothing to answer or to request. Once "No" is chosen for collection, the console skips the
  questions about encryption in transit and data deletion (check the exact wording in the console; if it asks
  anyway, the facts are: nothing is collected, so there is nothing to delete, and uninstalling the app or
  clearing its data removes the only file the app writes).
- [ ] Review the summary the console shows before saving: it must read "No data collected" and "No data shared".

## 9. Government apps

- [ ] **Is your app a government app?** No.

## 10. Financial features

- [ ] Choose "My app doesn't provide any financial features" (check the exact wording in the console). No payments,
  no banking, no loans, no crypto, no trading.

## 11. Health

- [ ] Choose "My app doesn't have any health features" (check the exact wording in the console). The "HP" of
  the game is a game score, not a health measure.

## 12. Store settings: category and contact details

- [ ] **App or game:** Game.
- [ ] **Category:** Board (Games, Board). If a tag list is shown, choose the ones that fit, such as chess and
  roguelike (check the exact wording in the console).
- [ ] **Contact email:** the author types it in the console. It is shown on the store listing, so use an address
  meant to be public. The app itself never shows an email: the feedback channel is GitHub issues.
- [ ] **Website:** `https://github.com/Orasz/chess-roguelike`
- [ ] **Phone:** leave empty (it is optional).
- [ ] **No donation link** in the listing or anywhere in the app during the beta.

## 13. Main store listing

Paste the files as they are (they have no trailing newline). The default language is English.

- [ ] **Default language:** English (United States), `en-US`.
  - App name: `store/listing/en-US/title.txt`
  - Short description: `store/listing/en-US/short_description.txt`
  - Full description: `store/listing/en-US/full_description.txt`
- [ ] **Add a translation:** Italian (Italy), `it-IT`, from `store/listing/it-IT/` (the same three files).
- [ ] **App icon:** `store/graphics/icon_512.png` (512 x 512, 32-bit PNG with alpha).
- [ ] **Feature graphic:** `store/graphics/feature_1024x500.png` (1024 x 500, 24-bit PNG, no alpha). It is drawn by
  `game/tools/make_store_art.gd` from the game's own art.
- [ ] **Phone screenshots:** the files of `store/screenshots/`, at least two and at most eight (they come with the
  screenshots task: if the folder is empty, this box waits).
- [ ] **Do not add** a promotional video, a donation link, a price or "free" claim in the short description, or any
  feature the build does not have (the listing says so in `tools/store/test_listing.py`).

## 14. Declaration: no permissions

- [ ] The app declares **no permissions**: not `INTERNET`, not storage, nothing. No permission declaration form
  applies, because the console only asks for one when an app requests a sensitive permission (check the exact
  wording in the console). The release screen should list no permissions for the bundle.
- [ ] Confirm it before uploading: `make check-aab` fails if the manifest declares any permission.
- [ ] If the console shows an **Advertising ID** declaration (it appears for apps that target Android 13 and
  later; check the exact wording in the console), answer that the app does **not** use an advertising ID.

## 15. Closed test, then production access

Production access for a new personal account needs a closed test with at least **12 testers opted in for 14
continuous days** (research §1.4). The 12 testers must not also be internal testers. After the 14 days, the
Dashboard offers "Apply for production", with a short questionnaire. The console's questions are not known
here, so the headings below are the topics the questionnaire is expected to cover: **check the exact wording in
the console** and use the drafts as the starting point of each answer.

### About the app

- [ ] **What is the app, and who is it for?**

  > Chess Roguelike is a free, open-source Android game for chess players aged 18 and over. The player walks a
  > top-down map, and every fight against an enemy is a chess position: a tactical puzzle from the Lichess puzzle
  > database, a fight in the theory of the Italian Game, or a strong enemy that makes the player convert an
  > advantage. A mistake costs HP in proportion to what it throws away, and the game explains it. The beta has one
  > zone and one opening. The app is offline, has no ads, no purchases, no account and no permissions, and it
  > collects no data. The source code is public under the GPLv3.

- [ ] **How does the app provide value to users?**

  > It makes chess practice into a small adventure: the player trains tactics and opening theory in a run with HP,
  > a potion and a map, and every wrong move is explained with an arrow and a sentence, so each mistake teaches
  > something.

- [ ] **Expected installs** (an estimate: change it if the author knows better)

  > A small audience, mostly chess players who find the project through its GitHub page. There is no advertising
  > and no marketing budget.

### About the closed test

- [ ] **How did you recruit your testers?**
  `TODO-AUTHOR`: say, in the author's own words, where the 12 or more testers came from (friends, a chess club, an
  online community, a mailing list) and how they were invited and asked to stay opted in for the 14 days. Only
  state what really happened.

- [ ] **What feedback did you receive, and what did you change because of it?**
  `TODO-AUTHOR`: summarise the real feedback (bugs, the difficulty of the fights, the texts, the screen on their
  phones) and the changes it caused, with the version codes if useful. Only state what really happened. The
  channels were the GitHub issues of the project and Play's private tester feedback.

### Production readiness

- [ ] **How do you know the app is ready for production?**

  > The release bundle is built and checked for Play's rules: targetSdk 36, 64-bit only, native libraries
  > aligned to 16 KB pages and stored uncompressed, and no permissions. It was tested on a real phone and by the
  > closed testers, and the repository has an automated test suite. The app needs no server and
  > collects no data, so there is no backend to scale, and the privacy policy is public and linked in the app and in
  > the listing. Crashes reported by Play's Android vitals will be read in the Play Console and fixed through GitHub
  > issues.

- [ ] **Do not claim** more than is true: no number of installs, ratings or tester counts that the console does
  not show.
