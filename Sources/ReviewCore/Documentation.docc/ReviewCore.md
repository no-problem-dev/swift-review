# ``ReviewCore``

Ask for App Store ratings only through the system prompt, at moments the app declares, and take feedback through a separate door.

@Metadata {
    @PageColor(orange)
}

## Overview

The system already decides whether a rating prompt appears, and it already asks "Enjoying this
app?". What is left to the app is **when** to call it, and that is where apps go wrong: on first
launch, in the middle of a task, right after a failure, or after a pre-prompt that sends unhappy
people elsewhere.

This module turns "when" into values and one pure function. The app declares its good outcomes
(``ReviewSignalKind``), the places that may ask (``ReviewMomentName``), what holds requests back
(``ReviewBlockerKind`` with a ``ReviewCooldown``), and the limits (``ReviewPolicy``).
``ReviewRules/decide(at:version:moment:state:policy:)`` answers with a ``ReviewDecision`` and the
first reason it failed, and ``ReviewPrompter`` records, decides and asks.

Feedback is separate on purpose: ``FeedbackDraft`` and ``FeedbackSender`` are never wired into the
rating flow, so the package offers no way to route unhappy people away from the rating prompt.

```swift
let policy = ReviewPolicy(
    timeZone: TimeZone(identifier: "Asia/Tokyo")!,
    moments: [.journalSaved: ReviewMomentRule(minimumSignals: 2)],
    signalCapPerScope: [.checkedIn: 1],
    cooldowns: [.paywallDismissed: .days(14), .error: .days(3)]
)

await prompter.record(.movementDecided, in: ReviewScope(trip.id))
await prompter.reach(ReviewMoment(.journalSaved, in: ReviewScope(trip.id)))
```

## Topics

### Deciding

- ``ReviewRules``
- ``ReviewPolicy``
- ``ReviewMomentRule``
- ``ReviewCooldown``
- ``ReviewDecision``
- ``ReviewSkipReason``

### Vocabulary

- ``ReviewSignalKind``
- ``ReviewMomentName``
- ``ReviewBlockerKind``
- ``ReviewScope``
- ``ReviewRequirement``
- ``ReviewMoment``
- ``ReviewSignal``
- ``ReviewBlocker``
- ``ReviewAsk``
- ``AppVersion``
- ``ReviewDay``

### Recording and asking

- ``ReviewPrompter``
- ``ReviewAttempt``
- ``ReviewAsker``
- ``ReviewAskOutcome``
- ``ReviewAbandonment``
- ``ReviewClock``
- ``SystemReviewClock``

### State

- ``ReviewState``
- ``ReviewStateStore``
- ``UserDefaultsReviewStateStore``
- ``InMemoryReviewStateStore``
- ``ReviewStoreError``

### The write-review link

- ``AppStoreID``
- ``WriteReviewLink``

### Feedback

- ``FeedbackDraft``
- ``Feedback``
- ``FeedbackKind``
- ``FeedbackReplyAddress``
- ``FeedbackAttachment``
- ``FeedbackDiagnostics``
- ``FeedbackLimits``
- ``FeedbackError``
- ``FeedbackSender``
- ``FeedbackDelivery``
- ``FeedbackMail``
- ``FeedbackPayload``
- ``HTTPFeedbackSender``

### Metrics

- ``ReviewMetrics``
- ``ReviewMetricEvent``
- ``ReviewMetricValue``
- ``NoReviewMetrics``
