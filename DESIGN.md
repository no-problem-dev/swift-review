# swift-review — design

Status: 0.2.0. Written 2026-10-01 from the tabisaki spec
`docs/spec/review-and-feedback.md` §7 (the split between what any app shares and what one app
decides) and the research behind it, `docs/research/reviews/README.md`. Revised 2026-11-08 to be
the base for every app in the family (studio `docs/app-shared-packages-design-2026-11-08.md`):
the defaults are now studio's rating rules (`knowledge/rating.md`, cited as R numbers), `AppVersion`
is the family's one version type, and a second kind of moment shows the app's own review screen
(§5.5).

A summary in Japanese is at the end ([日本語の要約](#日本語の要約)).

---

## 1. Purpose

Two jobs, kept apart on purpose:

1. **Ask for an App Store rating only through the system prompt, and only at moments the app has
   declared, when the person has had a good run and nothing has just gone wrong.** The package
   owns *when*. The system owns *whether* a prompt appears and what it says.
2. **Take feedback through a separate door that is open at any time**: a draft with a kind, text,
   an optional reply address, optional attachments and opt-in diagnostics, and a port to send it
   through mail or HTTP.

The two never meet. The rating flow has no branch that sends anyone to feedback, and feedback has
no hook into the rating flow, except that "sent feedback" can be recorded as a blocker so the app
does not ask for a rating right after someone complained.

## 2. Non-goals, and why

| Not provided | Why |
|---|---|
| A custom rating dialog, star picker, or anything that looks like the store's | App Review Guideline **5.6.1**: "Use the provided API to prompt users to review your app … we will disallow custom review prompts." |
| A pre-prompt ("Do you like this app? Yes / No") or any routing of unhappy people away from the prompt | The introduction to Guidelines §3 lists inflating rankings with "paid, incentivized, **filtered**, or fake feedback" as manipulation, with removal from the Developer Program as a possible result. A pre-prompt that only lets satisfied people reach the system prompt filters by sentiment. Google Play's In-App Review guidance forbids asking "Do you like the app?" before or during the flow outright. The system prompt itself already asks "Enjoying *App Name*?" (HIG, Ratings and reviews), so a pre-prompt asks the same question twice. **5.6.3** forbids manipulating any element of the store experience, reviews included |
| Incentives (credits, unlocked features, days of a subscription) | Guidelines §3 intro ("incentivized"); **3.2.2(x)**: apps "must not force users to rate the app, review the app … in order to access functionality". In Japan, the 2023-10 stealth-marketing rule under the Premiums and Representations Act makes asking only for good reviews, or rewarding them, a further risk |
| Calling the request from a button | `RequestReviewAction` "may not present an alert", so a button that sometimes does nothing reads as a bug (StoreKit documentation; HIG; rating.md R7). The write-review link is the button-shaped path (§9). The own-screen moment (§5.5) keeps to this: it has no path to the system at all |
| A screen in front of the system prompt | A screen that comes before the system prompt and decides who reaches it is the pre-prompt above. The own-screen moment (§5.5) is not one: no system prompt follows it from the package, everyone who reaches it sees the same screen, and nothing on it asks whether the person is satisfied (R3, R24) |
| The own review screen itself | rating.md R24: try it in one app and read the App Review outcome before spreading it. The package decides whether it may appear; the app draws it |
| Knowing whether the prompt was shown | The system does not report it. The package counts **calls**, never displays (§5.4) |
| Server-side or cross-device state | The system limit is per device and app. A request on another device does not use this one's allowance, so syncing would make the app ask less without making the system ask less |
| Replying to App Store reviews | An operations task (`asc reviews …`), not app code |

Apple's own numbers the defaults rest on: the system shows the prompt at most **three times in 365
days** per app; for someone who already rated, only in a new version and more than 365 days after
the last rating; never in TestFlight; every time in development builds. `SKStoreReviewController`
is deprecated in iOS 18 in favour of `RequestReviewAction` (iOS 16+).

## 3. Package structure

```
swift-review
├── ReviewCore      Foundation only. Vocabulary, pure decision, prompter, ports,
│                   UserDefaults/in-memory stores, write-review link, feedback values,
│                   mailto builder, HTTP sender over an injected transport, metrics port
├── ReviewSwiftUI   ReviewCore + SwiftUI + StoreKit (+ MessageUI on iOS). ReviewRequestBridge
│                   (the ReviewAsker), .reviewRequests(_:suppressed:delay:), MailFeedbackSender
│                   (OpenURLAction), MailComposerFeedbackSender + .feedbackMailComposer(_:)
└── ReviewTesting   ReviewCore. ManualReviewClock, RecordingReviewAsker,
                    RecordingReviewMetrics, RecordingFeedbackSender
```

| Product | Imports | Who imports it |
|---|---|---|
| `ReviewCore` | Foundation, os (for the lock) | Any layer that records signals or decides. No UI framework |
| `ReviewSwiftUI` | ReviewCore, SwiftUI, StoreKit, Observation, MessageUI and UIKit (iOS only) | **Only** the app target's root view |
| `ReviewTesting` | ReviewCore | Tests and test-support targets. Never a shipping target |

- **The manifest has no dependencies**, like `swift-calendar-date`. The DocC plugin is added in CI
  (`.github/workflows/docc.yml`). SwiftPM resolves dependencies per package, so anything declared
  here would land on every consumer.
- tools 6.2, Swift 6 language mode (strict concurrency), iOS 17 / macOS 14 (FAMILY_CHARTER §1).
  `RequestReviewAction` needs iOS 16 / macOS 13, so the floor is the family's, not StoreKit's.
  tvOS and watchOS have no review prompt and are not listed.

## 4. Domain model

The spec's names (left) map to these types. Every app-defined name is a `String`-backed value type
with `ExpressibleByStringLiteral`, so apps write `static let journalSaved: Self = "journal_saved"`.

| Spec | Type | Meaning |
|---|---|---|
| Signal (合図) | `ReviewSignalKind`, `ReviewSignal(kind, scope?, at)` | A good outcome the person caused |
| Grouping unit | `ReviewScope` | A trip, project or document. Signals and blockers can be scoped |
| Moment (場面) | `ReviewMomentName`, `ReviewMoment(name, scope?, ongoing, unmet)` | A declared place that may ask, plus what holds *right now* |
| App precondition | `ReviewRequirement` | Something only the app can check ("has an own trip"). Passed in `ReviewMoment.unmet` |
| Cooldown / blocker (止める出来事) | `ReviewBlockerKind`, `ReviewBlocker(kind, scope?, at)`, `ReviewCooldown(days, holdsForScope)` | Something that holds requests back for a while. State keeps only the latest per kind and scope |
| Ask (頼んだ記録) | `ReviewAsk(at, version, moment, scope?)` | One call to the system |
| Decision (判定) | `ReviewDecision.ask` / `.skip(ReviewSkipReason)` | With the first failing rule, its `stage` and a metrics `code` |
| Policy (方針の値) | `ReviewPolicy` | Every threshold, as values |
| State (状態) | `ReviewState`, schema version 1 | Install time, days of use, signals, blockers, asks |
| Own-screen moment | `ReviewScreenMoment(name, ongoing)`, `ReviewScreenRule(daysAfterRated)`, `ReviewScreenShow(at, version, moment)` | A place that may show the app's own review screen (§5.5) |
| — | `AppVersion` (`major.minor.patch`, `Granularity`) | The family's one version type (§4.1). "Once per version" at minor granularity by default |
| — | `ReviewDay` | A time-zone-free date, `YYYY-MM-DD`, read in the policy's zone |

### 4.1 `AppVersion`, the one version type

reading-memory (`UseCases/Launch/AppVersion.swift`), gamification-app (`ServerPrimarySwitch.swift`)
and this package each had one. This one is the one to keep, and the others move to it:

- `AppVersion("1.6")`, `AppVersion(bundle:)` (default `.main`, reads `CFBundleShortVersionString`),
  `AppVersion(major:minor:patch:)`. One to three numeric parts; anything else is `nil`
- Comparable part by part (`1.10.0 > 1.9.0`); `"1.6" == "1.6.0"`; `description` is always three parts
- `truncated(to:)` and `isSame(as:at:)` for "the same version at minor granularity"
- Not `ExpressibleByStringLiteral` on purpose: with it, `AppVersion("2.1b")` silently picks the
  literal initialiser (SE-0213) and traps instead of returning `nil`

Telling a fresh install from an upgrade (fresh / upgraded / same) needs the previous version
stored somewhere, which is swift-app-launch's job. This type only parses, compares and prints.

### 4.2 Built-in names

The names in the rating rules are built in so every app records and reports them the same way:
`ReviewMomentName.afterWhatsNew` (`after_whats_new`, the common catalog's value) and the blocker
kinds `paywallDismissed`, `error`, `feedbackSent`, `cancelScreenOpened` (with default cooldowns,
R25), `purchased` and `paywallShown` (for `ongoing` in that launch, R10). Signals stay the app's.

### Conditions in effect now vs. recorded blockers

A blocker kind can be used two ways:

- **Recorded**: `prompter.block(.paywallDismissed)` stores the time; the policy's
  `cooldowns[.paywallDismissed] = .days(14)` holds requests back for 14 days from the latest one.
- **Ongoing**: `ReviewMoment(…, ongoing: [.offline])` holds this one moment back and stores nothing.
  Offline, a sheet on screen, "the trip is in progress" are ongoing.

A blocker recorded **in a scope** holds every moment back for `days`, and with
`holdsForScope: true` additionally holds moments *in that same scope* until the scope is
forgotten. That one shape expresses tabisaki's "a trip with a missed connection is never the trip
we ask about, but the next trip may be asked about three days later".

## 5. The decision

```swift
public enum ReviewRules {
    public static func decide(
        at now: Date,
        version: AppVersion,
        moment: ReviewMoment,
        state: ReviewState,
        policy: ReviewPolicy
    ) -> ReviewDecision
}
```

The spec named it `decide(at:moment:state:policy:)`. The running version is an input too (it
decides "once per version"), and putting it in the policy or the moment would blur what those
mean, so it is an explicit argument. 0.2 adds `launchedAt:` (default `nil`, which skips the rule)
for "30 seconds after launch"; the prompter passes the time of its first `markActive()`. Nothing in
`ReviewRules` reads a clock, a time zone, a bundle or a store.

### 5.1 Order

The first failing rule is returned. Prerequisites come first so `passedPrerequisites` cleanly
separates "not yet" from "eligible but not now", which is what the metric needs.

| # | Stage | Rule | Reason |
|---|---|---|---|
| 1 | prerequisite | `isEnabled` | `.disabled` |
| 2 | prerequisite | moment declared in `policy.moments` | `.undeclaredMoment` |
| 3 | prerequisite | elapsed days since first launch ≥ `minimumDaysSinceInstall` (7, R9) | `.tooSoonAfterInstall(days:required:)` |
| 4 | prerequisite | distinct days of use (policy time zone, last `activeDayRetention` = 60 days) ≥ `minimumActiveDays` (0: the rules have none; tabisaki sets 3) | `.tooFewActiveDays` |
| 5 | prerequisite | `moment.unmet` is empty | `.requirementUnmet` |
| 6 | prerequisite | counted signals ≥ the moment's `minimumSignals` (3, R8) | `.tooFewSignals` |
| 7 | blocker | `moment.ongoing` is empty | `.ongoing` |
| 8 | blocker | no recorded blocker still cooling down (the longest hold is reported; defaults R25) | `.coolingDown(kind, until:)` |
| 9 | blocker | at least `minimumSecondsSinceLaunch` (30, R9) since `launchedAt` | `.tooSoonAfterLaunch(until:)` |
| 10 | limit | asks in this version (at `versionGranularity`) < `asksPerVersion` (1, R9) | `.alreadyAskedThisVersion` |
| 11 | limit | asks in this scope < `asksPerScope` (`nil`: no limit; tabisaki sets 1) | `.alreadyAskedInScope` |
| 12 | limit | elapsed days since the last ask ≥ `minimumDaysBetweenAsks` (60, R9) | `.tooSoonAfterLastAsk(until:)` |
| 13 | limit | asks in the rolling 365-day window < `maximumAsksPerYear` (3, R9) | `.yearlyLimitReached(until:)` |
| — | limit | another request is waiting for the screen (prompter only) | `.askInProgress` |
| — | prerequisite | state could not be read (prompter only) | `.stateUnavailable` |

Every `until` is the instant the rule stops failing, so a developer screen can show "next possible
request".

### 5.2 Counting signals

- A moment **with** a scope counts that scope's signals.
- A moment **without** a scope counts only **unscoped** signals recorded after the most recent
  ask, optionally limited to `unscopedSignalLookbackDays`. One run of good outcomes never earns two
  requests, and signals that belong to a trip or a document only ever count for a moment in that
  same scope.
- `ReviewMomentRule.countedSignals` restricts the kinds a moment counts (`nil` counts all).
- `ReviewPolicy.signalCapPerScope[kind]` caps how much one kind contributes per scope: ten
  check-ins on one trip count once.
- Signals stamped after `now` do not count.
- An undone action is taken back with `retract(_:in:)`, which removes the latest matching signal.

### 5.3 How an app declares what counts

The app owns its signals and moments, and every value it changes. The rating rules' blockers and
`afterWhatsNew` are built in (§4.2); an undeclared moment never asks.

```swift
extension ReviewSignalKind {
    static let movementDecided: Self = "movement_decided"
    static let stayAdded: Self = "stay_added"
    static let checkedIn: Self = "checked_in"
}
extension ReviewMomentName {
    static let journalSaved: Self = "journal_saved"     // T1
    static let splitSettled: Self = "split_settled"     // T2
    static let nextTripPlanned: Self = "next_trip_planned" // T3
}
extension ReviewBlockerKind {   // paywallDismissed, error, feedbackSent, cancelScreenOpened are built in
    static let tripDisrupted: Self = "trip_disrupted"
    static let offline: Self = "offline"
    static let inTrip: Self = "in_trip"
}

let policy = ReviewPolicy(
    timeZone: TimeZone(identifier: "Asia/Tokyo")!,
    minimumActiveDays: 3,                      // tabisaki's own rule
    moments: [
        .journalSaved: ReviewMomentRule(minimumSignals: 2),
        .splitSettled: ReviewMomentRule(minimumSignals: 2),
        .nextTripPlanned: ReviewMomentRule(minimumSignals: 2)
    ],
    signalCapPerScope: [.checkedIn: 1],
    cooldowns: ReviewPolicy.standardCooldowns.merging([
        .syncReverted: .days(3),
        .tripDisrupted: ReviewCooldown(days: 3, holdsForScope: true)
    ]) { $1 },
    minimumDaysBetweenAsks: 120,               // tabisaki's own rule
    asksPerScope: 1                            // once per trip
)
```

What the package cannot know stays in the app: which actions are signals (not the example trip,
not a companion's action), which state is "in trip", whether T3 is the person's second trip. The
app expresses those by not recording, by `ongoing`, or by `unmet`.

### 5.3.1 The defaults are the rating rules

There is one set of defaults, and it is studio's `knowledge/rating.md`. 0.1 took tabisaki's values
(3 days of use, 120 days, once per trip); the five other apps had written their own 15 to 250 lines
and ended up with 60 days, 120 days and "once for life". The defaults now carry the rule numbers,
so an app passes its moments and nothing else, and every departure is a line an app has to write.

| Value | Default | Rule |
|---|---|---|
| `minimumDaysSinceInstall` | 7 | R9 |
| `asksPerVersion` / `versionGranularity` | 1 / `.minor` | R9 |
| `minimumDaysBetweenAsks` | 60 | R9 (60 days apart still uses the system's three a year) |
| `maximumAsksPerYear` | 3 | R9, the system's limit |
| `minimumSecondsSinceLaunch` | 30 | R9 |
| `ReviewMomentRule.minimumSignals` | 3 | R8 (the third time it proved useful) |
| `cooldowns` | `standardCooldowns`: paywall closed 14, error 3, feedback sent 30, cancel screen 90 days | R10, R25 |
| `ReviewScreenRule.daysAfterRated` | 120 | R24, the value both existing own screens use |
| `.reviewRequests(delay:)` | 1.8 s | R8 (1.5 to 2 s after the animation stops) |
| `minimumActiveDays`, `asksPerScope` | 0, `nil` | no rule; tabisaki sets 3 and 1 |

There are no presets. A preset per app would be the three-way split again under another name.

### 5.4 Every call counts

The system never says whether it showed a prompt. A request is recorded as soon as the system was
called (`ReviewAskOutcome.requested`), shown or not. Not counting would let the app call at every
moment while the system stays quiet. A request the screen dropped before calling
(`.abandoned(…)`) is not counted. Starting over (account deletion, reinstall) never makes the
system prompt more often than it allows, because its own limit stays.

### 5.5 Two kinds of moment: the system prompt, and the app's own screen

"After What's New" is used two ways in the family. gamification-app and reading-memory show their
own review screen after the What's New sheet (rating.md R24); an app can instead call the system
prompt there. The two spend different things, so they are two types:

| | `ReviewMoment` (system prompt) | `ReviewScreenMoment` (own screen) |
|---|---|---|
| What happens | `reach` → `ReviewAsker` → `RequestReviewAction` | `present` returns `.ask`; the app shows its screen |
| Spends | One of the system's three prompts a year | Nothing of the system's |
| Declared in | `policy.moments` (`ReviewMomentRule`) | `policy.screens` (`ReviewScreenRule`) |
| Rules | All of §5.1 | Enabled, declared, `ongoing`, cooldowns, once per version, `daysAfterRated` since `markRated()` |
| Recorded as | `ReviewAsk` (counts toward every limit) | `ReviewScreenShow` (counts toward nothing else) |
| Metric | `review_requested` (common catalog) | `review_screen_shown` (app catalog, optional) |

**Why the screen is free of the install, signal, 60-day and yearly rules.** Those rules exist to
spend the system's small allowance well (R9). The screen does not touch it. It still respects
blockers, because a screen right after a paywall or an error is as badly timed as a prompt (R10,
R25). Who reaches it is decided by the launch order (swift-app-launch shows What's New only to
people who upgraded), which also keeps it out of onboarding and the first launch (R5).

**Why it does not contradict §2.** The two prohibitions are about what the package does:

- *No `requestReview` from a button.* `ReviewScreenMoment` has no asker and `present` has no path
  to StoreKit, so the type system keeps "show our screen" from becoming a system call. The
  screen's rate button belongs to the app; the package's button-shaped path is
  `WriteReviewLink` (R7: the link may always be there). An app that calls `requestReview` from
  that button (R24 ③) does it in its own code and carries R24's condition: one app first, and the
  review outcome before the others.
- *No pre-prompt.* A pre-prompt sits in front of the system prompt and lets only some people
  through. The own screen is not followed by a system prompt from the package, everyone who
  reaches it sees the same screen, and it never asks whether the person is satisfied (R3). The
  two kinds never chain: `present` does not call `reach`, and an app should not call both at the
  same moment.

**Why `rated` holds only the screen.** `markRated()` records that the person pressed the screen's
rate button. Whether they wrote a review is unknowable (R11), and the system already stops
prompting someone who rated, so the mark keeps only the app's own screen away for 120 days.

## 6. State and storage

```swift
public protocol ReviewStateStore: Sendable {
    func load() throws(ReviewStoreError) -> ReviewState?
    func save(_ state: ReviewState) throws(ReviewStoreError)
    func clear()
}
```

- `UserDefaultsReviewStateStore()` / `(suiteName:key:)` stores JSON under one key (default
  `review.state`). It holds the suite **name** and opens the suite per call, because `UserDefaults`
  is not `Sendable` and the family does not use `@unchecked Sendable` for this.
- `InMemoryReviewStateStore` (in `ReviewCore`, for previews and development builds) goes through the
  same encoded form, so it fails the same way a real store does.
- **Versioned**: the stored JSON carries `"schema": 1`. A newer schema is refused
  (`.newerSchema(found:supported:)`); the prompter then neither asks nor writes, so a downgrade
  cannot wipe what a newer build recorded. Unknown top-level fields are kept and written back.
- **Corrupt** data is refused (`.corrupt`), reported through metrics, and never silently replaced.
- **Pruning** after each write drops only what can no longer change an answer: signals older than
  `signalRetentionDays` (365), blockers whose cooldown is over (scope-holding ones stay until the
  scope is forgotten), asks older than 365 days except the latest per version.
- `forget(scope)` drops a scope's signals and blockers (a deleted trip); asks stay because they
  still count toward the limits. `reset()` clears everything (account deletion); the next
  `markActive()` is a fresh install.
- Dates are stored as seconds since 1970; days as `YYYY-MM-DD`; versions as `"1.4.0"`.
- 0.2 adds `screenShows` and `ratedAt` **without a schema bump**: both are optional in the stored
  form, so a 0.1 state reads as "never shown, never rated", and a 0.1 build keeps them as unknown
  fields and writes them back.

## 7. Recording and asking

```swift
public actor ReviewPrompter {
    public init(policy:version:store:asker:clock:metrics:)
    public func markActive()                                   // launch and every return to foreground
    public func record(_ kind: ReviewSignalKind, in scope: ReviewScope? = nil)
    public func retract(_ kind: ReviewSignalKind, in scope: ReviewScope? = nil)
    public func block(_ kind: ReviewBlockerKind, in scope: ReviewScope? = nil)
    public func forget(_ scope: ReviewScope)
    public func markRated()                                    // the own screen's rate button
    public func reset()                                        // account deletion
    public func evaluate(_ moment: ReviewMoment) -> ReviewDecision      // no side effects but the metric
    public func reach(_ moment: ReviewMoment) async -> ReviewAttempt    // decide, ask, record
    public func present(_ moment: ReviewScreenMoment) -> ReviewDecision // decide, record the show
}

public protocol ReviewAsker: Sendable {
    func requestReview(for moment: ReviewMoment) async -> ReviewAskOutcome
}
```

`reach` sets an in-progress flag across the `await`, so a second moment arriving while the first
waits for the screen is answered `.askInProgress` instead of asking twice.

### 7.1 The StoreKit adapter (`ReviewSwiftUI`)

`RequestReviewAction` exists only in the SwiftUI environment and has no public initialiser, so it
cannot be called from the prompter or faked. The seam is therefore one step earlier:

- `ReviewRequestBridge` (`@MainActor @Observable`) conforms to `ReviewAsker`. It holds at most one
  pending request and suspends the prompter until a view resolves it.
- `.reviewRequests(bridge, suppressed: isSheetShown, delay: .milliseconds(1800))` on the root view takes the
  pending request, checks `scenePhase == .active` and `!suppressed`, waits `delay`, checks again,
  calls `requestReview()` and resolves `.requested`.
- It resolves `.abandoned(…)` (not counted) if no view is attached (`.noHost`), one is already
  pending (`.alreadyPending`), the scene leaves the foreground (`.sceneInactive`), something is
  presented (`.obstructed`), or the view goes away (`.interrupted`).

This matches the spec's §2-5 ("check the scene is active and no sheet is showing, wait, skip and do
not count if the screen changed meanwhile"). The default wait is 1.8 seconds (R8).

## 8. Metrics

```swift
public protocol ReviewMetrics: Sendable { func record(_ event: ReviewMetricEvent) }

public enum ReviewMetricEvent {
    case evaluated(ReviewMoment, ReviewDecision)        // review_prompt_evaluated  moment, eligible, asked, stage, reason
    case requested(ReviewMoment, ordinal:)              // review_requested         moment   ← common catalog
    case abandoned(ReviewMoment, ReviewAbandonment)     // review_prompt_abandoned  moment, reason
    case stateUnavailable(ReviewStoreError)             // review_state_unavailable reason
    case screenEvaluated(ReviewScreenMoment, ReviewDecision) // review_screen_evaluated moment, shown, stage, reason
    case screenShown(ReviewScreenMoment)                // review_screen_shown      moment
    case writeReviewLinkOpened                          // review_link_opened
    case feedbackOpened(source:)                        // feedback_opened          source
    case feedbackSent(kind:includesDiagnostics:delivery:) // feedback_sent          kind, diagnostics, channel
}
```

The prompter sends the first six; the app sends the rest through the same port.

**`review_requested` is the only one in the common catalog** (`swift-analytics`
`Schema/common/common.yaml`, `review_requested { moment }`, `moment` an extensible enum with
`after_whats_new`). Its parameters are exactly the catalog's: the app version is the envelope's,
and `ordinal` stays on the case for an app that adds R20's `count` in its own catalog.
`event.isInCommonCatalog` marks it. The others are optional; an app that sends them declares them
in its own catalog. An own-screen show is never `review_requested`, because the system was not
called.

The port is a protocol, `ReviewMetrics`, or a closure through `ReviewMetricsHandler { event in … }`. Parameters use
`ReviewMetricValue` (`text`, `count`, `flag`), which map one to one onto `swift-analytics`'
`AnalyticsValue`. They never carry the scope's identifier or text the person wrote.

**There is no analytics adapter target.** It would make `swift-analytics` a dependency of every
consumer, and in tabisaki, which uses `swift-analytics` by local path during development, a URL
dependency on the same package would collide with the path (SwiftPM silently picks the path). The
bridge is about twenty lines in the app:

```swift
import AnalyticsCore
import ReviewCore

struct ReviewAnalyticsEvent: AnalyticsEvent {
    let base: ReviewMetricEvent
    var name: String { base.name }
    var parameters: [String: AnalyticsValue] {
        base.parameters.mapValues {
            switch $0 {
            case let .text(value): .text(value)
            case let .count(value): .count(value)
            case let .flag(value): .flag(value)
            }
        }
    }
    var kind: EventKind { .outcome }
    var dedup: DedupScope { .always }
}

struct AnalyticsReviewMetrics: ReviewMetrics {
    let client: any AnalyticsClient
    func record(_ event: ReviewMetricEvent) { client.track(ReviewAnalyticsEvent(base: event)) }
}
```

An app whose own names differ (tabisaki's `review_prompt_eligible` with `trigger` and
`blocked_by`) maps in the same place: `evaluated` with `decision.passedPrerequisites` becomes
`review_prompt_eligible`, `reason.code` becomes `blocked_by`.

## 9. The write-review link

`AppStoreID("1585901351")` accepts digits only, so a placeholder build setting such as
`APP_STORE_ID` yields `nil` and the settings row can be hidden. `WriteReviewLink.url(for:)` builds
`https://apps.apple.com/app/id<ID>?action=write-review` (the form in Apple's
"Requesting App Store reviews" sample). Pressing it is the person's choice; it is not counted
toward any limit, and the app records `writeReviewLinkOpened` if it wants the metric.

## 10. Feedback

| Type | Role |
|---|---|
| `FeedbackKind` | `bug`, `request`, `other`; apps may add more |
| `FeedbackDraft` | What the screen holds: kind, text, typed reply address, attachments, the diagnostics the app *could* attach, `includesDiagnostics` (**default `false`**). `diagnosticsPreview` is exactly what would be sent |
| `validated(limits:) throws(FeedbackError) -> Feedback` | Trims the text; refuses empty, over-long (default 1,000), a malformed reply address, too many (1) or too large (10 MB) attachments. Diagnostics are carried only when opted in |
| `FeedbackDiagnostics` | Ordered `key: value` entries. **The app picks the entries**; the type carries no content of its own |
| `FeedbackSender` | `send(_:) async throws(FeedbackError) -> FeedbackDelivery` (`.handedToMail`, `.queued`, `.delivered(receipt:)`) |
| `FeedbackMail` | Builds a `mailto:` link with app-supplied labels, so the mail is in the app's language. `+` is escaped (mail apps read it as a space). Refuses attachments (`.attachmentsUnsupported`) rather than dropping them |
| `MailFeedbackSender` (`ReviewSwiftUI`) | Opens that link through `OpenURLAction`; `.noMailClient` when nothing accepts it |
| `MailComposerFeedbackSender` + `.feedbackMailComposer(_:)` (`ReviewSwiftUI`) | Hands the feedback to a view at the root, which presents `MFMailComposeViewController` with the attachments (one screenshot) over whatever is on top, sheets included (a SwiftUI `.sheet` on the root cannot appear over an open sheet). Sent or saved → `.handedToMail`; closed → `.cancelled`. Without a mail account it falls back to the `mailto:` link **without** the attachments (`url(for:omittingAttachments: true)`), so the person can still attach the file by hand. The sender itself has no MessageUI and is tested on macOS; the presenting modifier is iOS only |
| `FeedbackPayload`, `HTTPFeedbackSender` | JSON (`kind`, `text`, optional `replyAddress`, optional `diagnostics`, `attachments` as base64) posted through a **transport closure the app supplies** |

The HTTP sender does not open connections itself. The family rule is that HTTP goes through
`swift-http-transport` (FAMILY_CHARTER §3), and an app usually already has an authenticated client
(tabisaki: a generated OpenAPI client with App Check). Taking a closure keeps the package free of
that dependency and leaves auth, retries and logging where they already are.

## 11. Testing

`ReviewTesting`:

| Fake | Stands in for |
|---|---|
| `ManualReviewClock` | The clock; `advance(days:)`, `advance(hours:)`, `set(_:)` |
| `RecordingReviewAsker` | `ReviewRequestBridge`; records moments, answers a preset outcome, `answer(_:)` to change it |
| `RecordingReviewMetrics` | The metrics port; `events`, `names`, `reset()` |
| `RecordingFeedbackSender` | A feedback channel; records, answers a preset `Result` |

`InMemoryReviewStateStore` lives in `ReviewCore` because previews use it too. All fakes are
`Sendable` through a small `package` lock type over `OSAllocatedUnfairLock`, with no
`@unchecked Sendable` anywhere in the package (`Mutex` would need iOS 18 / macOS 15).

The rules are tested as pure functions (`ReviewRules.decide`) with fixed instants; the prompter
is tested with the fakes; the bridge is tested by attaching a host directly. What cannot be tested
is whether iOS shows the prompt: that is the system's call, and the spec adds no UI test for it.

## 12. Versioning, platforms, concurrency

- Semantic versioning, bare tags (`0.1.0`), computed by `scripts/release.sh` from the public API
  diff (family template). 0.x consumers pin `.upToNextMinor(from:)`.
- iOS 17+ / macOS 14+. Linux is not a target (`os` lock, StoreKit).
- Swift 6 language mode. Everything public is `Sendable`. Isolation: `ReviewPrompter` is an actor;
  `ReviewRequestBridge` and `MailFeedbackSender` are `@MainActor`; everything else is value types.
  Builds cleanly in consumers that enable `NonisolatedNonsendingByDefault` and
  `InferIsolatedConformances` (tabisaki does).
- `ReviewDay` duplicates a sliver of `swift-calendar-date`'s `LocalDate`. Depending on it would be
  the only dependency, and tabisaki uses it by path during development, which would collide with a
  URL dependency. Revisit when both are tagged.

## 13. Integrating into tabisaki

tabisaki's layer rules (AGENTS.md, `docs/architecture/system.md` §3-1) decide where each product
goes.

| tabisaki module | Imports | What it does with it |
|---|---|---|
| Domain, Planning, SDUI, Words, Outside | nothing from this package | Domain stays Foundation + CalendarDate + SyncCore |
| Presentation | nothing | The feedback screen keeps its own `FeedbackSender` protocol and draft state as the spec's §8 says; Composition maps between them and `ReviewCore` (decision 4) |
| **Composition** (AppSupport) | `ReviewCore` | `ReviewPrompting` shrinks to tabisaki's names and values (§5.3), builds the `ReviewPrompter` with `UserDefaultsReviewStateStore(key: "reviewPrompt.state")`, a `ReviewClock` over its `TripClock`, and a metrics bridge to its telemetry. `AppScreenSources+Review.swift` records signals and blockers in the existing screen ports and calls `reach` at T1–T3. Account deletion calls `reset()`; trip deletion calls `forget(_:)` |
| **DeviceTesting** / `DeviceFlowTests` | `ReviewTesting` | `RecordingReviewAsker` replaces the planned `RecordingReviewHost`; `ReviewPromptFlowTests` runs the production assembly with it |
| **App target** (`ios/App/`) | `ReviewSwiftUI` | `Production/ReviewPromptHost.swift` owns a `ReviewRequestBridge` and a `MailComposerFeedbackSender`, applies `.reviewRequests(bridge, suppressed: …)` and `.feedbackMailComposer(_:)` at the root, and hands both to the assembly as its `ReviewAsker` and `FeedbackSender`. The only StoreKit import in the app |
| Device | — | The mail composer lives in `ReviewSwiftUI` (decision 3), so tabisaki's Device has no MessageUI code |

Mapping tabisaki's rules onto the package:

| tabisaki rule | How |
|---|---|
| 7 days, 3 days of use (Japan time), 2 signals | 7 days is the default; `timeZone: Asia/Tokyo`, `minimumActiveDays: 3`, `minimumSignals: 2` per moment are passed |
| Check-ins count once per trip | `signalCapPerScope: [.checkedIn: 1]` |
| Example trip, companions, undone actions | Not recorded; undo calls `retract` |
| Has an own trip; T3 only after finishing a trip | `unmet: [.hasOwnTrip]`, `unmet: [.hasFinishedTrip]` |
| Not during a trip; offline; a sheet showing | `ongoing: [.inTrip]`, `ongoing: [.offline]`; sheets through `suppressed:` |
| Paywall 14, errors and reverted sync 3, feedback 30, cancel screen 90 days | `standardCooldowns` plus `syncReverted` |
| Missed connection: never that trip's T1/T2; T3 after 3 days | `block(.tripDisrupted, in: trip)` with `ReviewCooldown(days: 3, holdsForScope: true)` |
| Once per x.y, 120 days, 3 per 365 days, once per trip | Once per x.y and 3 per 365 days are defaults; `minimumDaysBetweenAsks: 120` and `asksPerScope: 1` are passed |
| Not synced; cleared on account deletion, not on sign-out | Device `UserDefaults`; `reset()` only from account deletion |

Wiring steps, in tabisaki's order: add `.package(path: "../../../../SwiftPackages/swift-review")`
to `ios/Packages/AppSupport/Package.swift` (and the product to `project.yml` for the app target),
switching to `.upToNextMinor(from: "0.2.0")` once tagged (AGENTS.md: path dependencies switch to
URL on release); add `ReviewCore` to Composition's and `ReviewTesting` to DeviceTesting's allowed
lists in system.md §3-1 and the `ModuleBoundaryTests` table.

## 14. Implemented vs. designed-only

| Piece | State |
|---|---|
| Vocabulary, `ReviewRules.decide`, `ReviewState` with schema and unknown fields, pruning | Implemented, tested |
| `ReviewPrompter` | Implemented, tested with fakes |
| `UserDefaultsReviewStateStore`, `InMemoryReviewStateStore` | Implemented, tested |
| `ReviewRequestBridge`, `.reviewRequests` | Implemented; the bridge is tested, the modifier is compiled for iOS and macOS but not run (it needs a scene) |
| `WriteReviewLink`, `AppStoreID` | Implemented, tested |
| Feedback values, `FeedbackMail`, `MailFeedbackSender`, `FeedbackPayload`, `HTTPFeedbackSender` | Implemented, tested |
| Fakes | Implemented |
| Analytics bridge | **Designed only**: the snippet in §8, by decision 2 |
| `MailComposerFeedbackSender`, `.feedbackMailComposer(_:)` | Implemented; the sender is tested, the modifier is compiled for iOS but not run (it needs a scene and a mail account) |
| Feedback outbox (send when back online) | **Designed only**, and app-side: the package defines `.queued` |
| Remote kill switch | `ReviewPolicy.isEnabled` only; fetching it is the app's |
| Own-screen moment (`ReviewScreenMoment`, `present`, `markRated`) | Implemented, tested. The screen is the app's |
| Moving the other apps onto 0.2 | Designed: README "Moving an app's own code onto this package" |

## 15. Decisions on the open questions

Answered by the tabisaki owner on 2026-10-01.

| # | Question | Decision |
|---|---|---|
| 1 | `decide` takes `version:` in addition to the spec's `at:moment:state:policy:` | **Keep** the argument (§5) |
| 2 | Analytics: an in-app snippet, or a `swift-review-analytics` package | **The in-app snippet** (§8). No separate package. tabisaki wires it once its telemetry events exist |
| 3 | The mail stage and a screenshot | **A mail composer** in `ReviewSwiftUI` that carries one attachment; `mailto:` stays as the fallback when Mail is not set up (§10) |
| 4 | Should tabisaki's Presentation import `ReviewCore` | **No.** Presentation keeps its own types; Composition maps between them (§13) |
| 5 | Language of `errorDescription` | **English**, matching `swift-analytics` |
| 6 | Days of use counted within the last 60 days | **Intended** |
| 7 | What an unscoped moment counts | **Only unscoped signals** (§5.2) |

---

## 日本語の要約

**何のためのパッケージか。** App Store の評価を、iOS の評価のダイアログ（`RequestReviewAction`）だけで、アプリが宣言した場面でだけ頼む。頼む時期を値と1つの純粋な関数にする。アプリへの要望は、評価とは別の入り口で、いつでも受け取る。

**作らないもの。** 自前の星の画面・「気に入っていますか？」の前置き・満足した人だけを App Store へ送る分岐・見返り・ボタンからの依頼。審査ガイドライン 5.6.1（独自のレビューの依頼を認めない）、3章の前書き（「選別した（filtered）」評価や見返りつきの評価は操作に当たる）、3.2.2(x)（評価を機能の条件にしない）、5.6.3（ストアの体験の操作を認めない）、Google Play の前置きの禁止、iOS のダイアログ自体が「楽しんでいますか？」と聞くこと（HIG）、景品表示法のステルスマーケティングの規制が理由。

**構成。** `ReviewCore`（Foundation だけ。語彙・判定・`ReviewPrompter`・口・UserDefaults の置き場所・書く画面のリンク・要望の値と送り口）、`ReviewSwiftUI`（StoreKit を import する唯一のターゲット）、`ReviewTesting`（偽物）。外部の依存は無い。

**判定。** `ReviewRules.decide(at:version:moment:state:policy:launchedAt:)` は時計も端末の時間帯も読まない純粋な関数。前提（インストールから7日・アプリの前提・合図3回）→ 止める出来事（いまの条件・期間の残る出来事・起動から30秒）→ 上限（版ごとに1回・前回から60日・365日に3回）の順に見て、最初に当たった理由を返す。iOS は出したかを返さないので、呼んだ回をすべて数える。

**既定は rating.md の値で1つだけ（0.2）。** 7日（R9）・版ごとに1回（R9）・前回から60日（R9）・365日に3回（R9）・起動から30秒（R9）・合図3回（R8）・ペイウォールを閉じて14日／エラーから3日／要望を送って30日／解約の画面から90日（R25）・画面が落ち着いてから1.8秒（R8）。プリセットは作らない。開いた日の数と範囲ごとの回数は rating.md に無いので既定では効かない（tabisaki は3日・1回を自分で渡す）。

**瞬間は2種類（0.2）。** OS の評価のダイアログを呼ぶ `ReviewMoment` と、アプリ自前の評価のお願いの画面を出すだけの `ReviewScreenMoment`。自前の画面は OS の年3回の枠を使わないので、インストールからの日数・合図・60日・365日の規則を当てず、版ごとに1回と「星をつける」を押してからの日数（120日）だけを持つ。止める出来事（ペイウォール・エラー）は当てる。自前の画面の瞬間には OS を呼ぶ道が無いので、「ボタンから requestReview を呼ばない」に反しない（画面のボタンはアプリの物で、パッケージが勧めるのは書く画面のリンク）。後ろに OS のダイアログが続かず、全員に同じ画面を出し、満足かを聞かないので「前置き」にも当たらない。画面そのものは R24 のとおりアプリが持つ。

**`AppVersion`（0.2）。** 一家の版の型の正本。読む・比べる・表すだけで、前回の版との変化（新規・更新・同じ）は swift-app-launch が持つ。`ExpressibleByStringLiteral` にはしない（`AppVersion("2.1b")` が nil でなく落ちるため）。

**状態。** 端末だけに置き、同期しない。版の番号つきの JSON で、新しい版の形は読まず書き換えもしない。知らない項目は残して書き戻す。アカウントの削除で全部を消し、旅行の削除でその範囲の合図と止める出来事を消す。

**計測。** `ReviewMetrics` の口（またはクロージャの `ReviewMetricsHandler`）に、判定・頼んだ・取りやめた・状態を読めなかった・自前の画面の判定と表示・書く画面のリンク・要望の画面・要望を送った、を出す。共通カタログにあるのは `review_requested { moment }` だけで、引数はカタログと同じ（版は封筒が持つ）。値は swift-analytics の `AnalyticsValue` と1対1。swift-analytics への依存は置かず、アプリの中の20行ほどでつなぐ（tabisaki は swift-analytics を path で頼るので、URL の依存とぶつかる）。

**要望。** 種類・本文・返信用のメール（任意）・添付・診断の情報（既定はオフ。表示した行と送る行は同じ）。送り口は `mailto:` のメール（添付は運べないので、添付があれば送らずに失敗にする）と、アプリが渡す送信の関数で POST する HTTP。

**tabisaki での置き場所。** `ReviewCore` は Composition だけが import する（Domain・Planning・Presentation は import しない）。`ReviewSwiftUI` はアプリのターゲットの `ReviewPromptHost` だけ。`ReviewTesting` は DeviceTesting とテスト。公開の版が付くまでは path の依存、付いたら `.upToNextMinor(from: "0.2.0")` に切り替える。

**決めたこと（§15）。** `decide` の `version:` 引数は残す。計測の橋はアプリの中の20行のまま。メールの段のスクリーンショットは `ReviewSwiftUI` のメールの作成画面（添付1つ）で運び、メールの設定が無い端末では添付を外した `mailto:` に戻る。tabisaki の Presentation は `ReviewCore` を import せず、Composition が写す。エラーの文は英語。開いた日を直近60日で数えるのは意図どおり。範囲の無い場面は、範囲の無い合図だけを数える。
