# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

First release, planned as 0.1.0.

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
- `ReviewTesting`: `ManualReviewClock`, `RecordingReviewAsker`, `RecordingReviewMetrics`,
  `RecordingFeedbackSender`.

### Decisions

- No custom rating dialog, pre-prompt, sentiment routing or incentive (App Review Guidelines 5.6.1,
  3.2.2(x), 5.6.3, and §3's "filtered" feedback).
- No dependencies. The `swift-analytics` bridge is a short adapter in the app (DESIGN.md §8).
