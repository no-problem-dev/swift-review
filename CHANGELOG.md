# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-11-08

### Changed

- The own-screen moment (`ReviewScreenMoment`, `present(_:)`) now waits the days since install,
  `ReviewPolicy.minimumDaysSinceInstall` (7) by default, and reports `.tooSoonAfterInstall` as a
  prerequisite. Why by default (rating.md R5, R9, R24; DESIGN.md §5.5): the 7 days are not only
  about spending the system's allowance, but about asking someone who has not yet used the app, who
  rates it low. Reaching What's New does not mean that time has passed (installed 1.6 yesterday,
  updated to 1.7 today), and the screen's rate button may call the system prompt (R24 ③). It is a
  line drawn by behaviour, so it keeps R3 and "the same screen for everyone". A screen that should
  not wait sets `ReviewScreenRule(minimumDaysSinceInstall: 0)`.

### Added

- `ReviewScreenRule.minimumDaysSinceInstall` (`nil` follows the policy, `0` turns it off).
- `ReviewScreenMoment(_:ongoing:unmet:)`: the app's own prerequisites, such as "has received what
  the app promises", checked as a prerequisite (`.requirementUnmet`) like a `ReviewMoment`'s,
  instead of being passed as an `ongoing` blocker.
- `ReviewPrompter.backdateInstall(to:)`: moves the recorded install time back to an earlier first
  use the app knows of, for an app that adopted the package after it had users. Only moves it
  earlier.

## [0.2.1] - 2026-11-08

### Added

- `UserDefaultsReviewStateStore(defaults:key:)` takes a `UserDefaults` instance the app holds
  (an App Group suite, or one a test or scenario set up), `.standard` by default. The store stays
  `Sendable`. It replaces `init(key:)`, so `init()` and `init(key:)` calls compile as before;
  `init?(suiteName:key:)` is unchanged.

## [0.2.0] - 2026-11-08

The base for every app in the family (studio `docs/app-shared-packages-design-2026-11-08.md`).

### Changed (breaking)

- `ReviewPolicy` defaults are studio's rating rules (`knowledge/rating.md`), one set, no presets:
  `minimumDaysBetweenAsks` 120 → **60** (R9), `minimumActiveDays` 3 → **0** (no such rule),
  `asksPerScope` 1 → **`nil`** (no such rule), `cooldowns` `[:]` → **`standardCooldowns`**
  (paywall closed 14, error 3, feedback sent 30, cancel screen 90 days; R25), new
  `minimumSecondsSinceLaunch` **30** (R9). `timeZone` defaults to `.current` and `moments` to `[:]`.
- `ReviewMomentRule(minimumSignals:)` defaults to **3** (R8).
- `.reviewRequests(_:suppressed:delay:)` waits **1.8 s** by default (was 1 s; R8).
- `ReviewMetricEvent.requested(_:version:ordinal:)` → `requested(_:ordinal:)`, named
  **`review_requested`** (was `review_prompt_requested`) with only **`moment`** (was also
  `app_version` and `nth`), matching the common analytics catalog. The version is the envelope's.
- Built-in `ReviewBlockerKind`s `paywallDismissed`, `error`, `feedbackSent`, `cancelScreenOpened`,
  `purchased`, `paywallShown`. An app that declared the same names in an extension gets an
  ambiguity error.
- New `ReviewSkipReason` cases (`tooSoonAfterLaunch`, `alreadyShownThisVersion`,
  `ratedRecently`): exhaustive `switch`es need them.

### Added

- The own-screen moment: `ReviewScreenMoment`, `ReviewScreenRule(daysAfterRated: 120)`,
  `ReviewPolicy.screens`, `ReviewRules.decide(at:version:screen:state:policy:)`,
  `ReviewPrompter.present(_:)` and `markRated()`, `ReviewScreenShow`, and the metrics
  `review_screen_evaluated` and `review_screen_shown`. It never calls the system (DESIGN.md §5.5).
- `ReviewState.screenShows` and `ratedAt`, stored without a schema bump (0.1 states read as empty).
- `ReviewRules.decide(…, launchedAt:)` and `ReviewSkipReason.tooSoonAfterLaunch(until:)`.
- `ReviewMomentName.afterWhatsNew` (`after_whats_new`).
- `ReviewMetricsHandler` (a closure as the metrics port) and `ReviewMetricEvent.isInCommonCatalog`.
- `AppVersion` is documented as the family's one version type; `AppVersion(bundle:)` defaults to
  `.main`; `isSame(as:at:)`.

### Migration from 0.1

1. Delete your own `ReviewBlockerKind` declarations of `paywall_dismissed`, `error`,
   `feedback_sent`, `cancel_screen_opened`; the built-in ones have the same raw values, so stored
   state keeps working.
2. If you relied on the old defaults, pass them: `minimumActiveDays: 3`,
   `minimumDaysBetweenAsks: 120`, `asksPerScope: 1` (tabisaki does). If you passed `cooldowns:`,
   it still replaces the defaults; merge with `ReviewPolicy.standardCooldowns` to keep them.
3. Rename `review_prompt_requested` to `review_requested` in your analytics catalog and drop its
   `app_version` and `nth` parameters. Replace `.requested(m, version: v, ordinal: n)` with
   `.requested(m, ordinal: n)`.
4. Handle the new `ReviewSkipReason` cases in any exhaustive `switch`.
5. If your prompter is created before the first screen, the 30-second rule now holds requests at
   the start of each launch. Pass `minimumSecondsSinceLaunch: 0` only with a reason.

## [0.1.0] - 2026-10-01

First release.

### Added

- `ReviewCore`, Foundation only:
  - The vocabulary an app declares: `ReviewSignalKind`, `ReviewMomentName`, `ReviewBlockerKind`,
    `ReviewScope`, `ReviewRequirement`, and the records `ReviewSignal`, `ReviewBlocker`, `ReviewAsk`,
    `ReviewMoment` (with conditions in effect now and unmet app prerequisites).
  - `ReviewPolicy`, every threshold as a value: days since install (7), days of use in a chosen time
    zone (3, within the last 60), signals per moment with per-kind caps, cooldowns per blocker (with
    `holdsForScope`), once per version at minor granularity, 120 days between requests, at most 3
    requests in any 365 days, once per scope.
  - `ReviewRules.decide(at:version:moment:state:policy:)`, a pure function that returns `.ask` or the
    first failing rule in the order prerequisites → blockers → limits, with `stage`, a metrics `code`
    and, where it applies, the instant the rule stops failing.
  - `ReviewState`, stored as JSON with schema version 1. A newer schema is refused and never
    overwritten; unknown top-level fields are kept; pruning drops only what cannot change an answer.
  - `ReviewStateStore` with `UserDefaultsReviewStateStore` and `InMemoryReviewStateStore`.
  - `ReviewPrompter`, an actor that records signals and blockers, counts days of use, decides, hands
    requests to a `ReviewAsker`, and records every call the system received. `reset()` for account
    deletion, `forget(_:)` for a deleted scope, `retract(_:in:)` for an undone action.
  - `AppVersion`, `ReviewDay`, `AppStoreID` and `WriteReviewLink`
    (`https://apps.apple.com/app/id<ID>?action=write-review`).
  - Feedback: `FeedbackDraft` (diagnostics off by default; the preview is what is sent), `Feedback`,
    `FeedbackKind`, `FeedbackDiagnostics`, `FeedbackLimits`, `FeedbackError`, the `FeedbackSender`
    port, `FeedbackMail` (`mailto:`), `FeedbackPayload` and `HTTPFeedbackSender` over a transport
    the app supplies.
  - `ReviewMetrics` and `ReviewMetricEvent`, with parameters that map one to one onto
    `swift-analytics`' `AnalyticsValue`.
- `ReviewSwiftUI`: `ReviewRequestBridge` and `.reviewRequests(_:suppressed:delay:)`, which call
  `RequestReviewAction` once the scene is active and nothing is presented, and drop the request
  (uncounted) otherwise; `MailFeedbackSender` over `OpenURLAction`.
- `ReviewSwiftUI`: `MailComposerFeedbackSender` and `.feedbackMailComposer(_:)`, which show the
  system mail composer with one attachment and fall back to a `mailto:` link without attachments
  when the device has no mail account. `FeedbackError.cancelled` for a composer closed unsent;
  `FeedbackMail.url(for:omittingAttachments:)` for that fallback.
- `ReviewTesting`: `ManualReviewClock`, `RecordingReviewAsker`, `RecordingReviewMetrics`,
  `RecordingFeedbackSender`.

### Decisions

- No custom rating dialog, pre-prompt, sentiment routing or incentive (App Review Guidelines 5.6.1,
  3.2.2(x), 5.6.3, and §3's "filtered" feedback).
- No dependencies. The `swift-analytics` bridge is a short adapter in the app (DESIGN.md §8).
- A moment without a scope counts only unscoped signals; scoped signals count only for a moment in
  the same scope.
- The open questions of DESIGN.md §15 are decided: keep `version:` on `decide`, keep the analytics
  snippet in the app, a mail composer for the screenshot, English error descriptions, days of use
  within the last 60 days.
