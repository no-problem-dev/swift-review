English | [日本語](./README.ja.md)

# swift-review

Ask for App Store ratings only through the system prompt, at moments your app declares, with every threshold as a value and the decision as one pure function. Take feedback through a separate door.

![Swift](https://img.shields.io/badge/Swift-6.2-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017%20%7C%20macOS%2014-blue.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

iOS already decides whether a rating prompt appears, and it already asks "Enjoying this app?". What
is left to the app is **when** to call it — and that is where apps go wrong: on first launch, in the
middle of a task, right after an error or a declined paywall, or after a "Do you like us?"
pre-prompt that sends unhappy people elsewhere (which App Review treats as filtering reviews).

This package writes "when" down. The app declares its good outcomes, the places that may ask, what
holds requests back and for how long, and the limits. One function answers *ask* or *skip, because…*.

## Features

- **The system prompt only.** `RequestReviewAction`, called from the view tree. No custom dialog, no
  pre-prompt, no sentiment branch, no incentives — there is no API for any of them (Guidelines 5.6.1,
  3.2.2(x), and §3's "filtered" feedback)
- **A pure decision with reasons.** `ReviewRules.decide(at:version:moment:state:policy:)` reads no
  clock, time zone or store, and returns the first failing rule: prerequisites → blockers → limits
- **Thresholds as values.** Days since install, days of use (in a time zone you choose), signals per
  moment, cooldowns per blocker, once per version, days between requests, a rolling 365-day cap
- **Every call counts.** The system never says whether it showed a prompt, so calls are counted,
  shown or not; a request the screen dropped before calling is not
- **Device-only, versioned state.** JSON with a schema number; a newer schema is never overwritten,
  unknown fields survive, account deletion resets it
- **Feedback, separately.** A draft with opt-in diagnostics (what you preview is what is sent), a
  `mailto:` channel and an HTTP channel over your own transport
- **No dependencies.** StoreKit and SwiftUI are confined to `ReviewSwiftUI`

## Quick Start

Declare what counts:

```swift
import ReviewCore

extension ReviewSignalKind {
    static let tripBooked: Self = "trip_booked"
    static let journalSaved: Self = "journal_saved"
}
extension ReviewMomentName {
    static let afterJournal: Self = "after_journal"
}
extension ReviewBlockerKind {
    static let paywallDismissed: Self = "paywall_dismissed"
    static let error: Self = "error"
    static let offline: Self = "offline"
}

let policy = ReviewPolicy(
    timeZone: .current,
    moments: [.afterJournal: ReviewMomentRule(minimumSignals: 2)],
    cooldowns: [.paywallDismissed: .days(14), .error: .days(3)]
)
```

Give the root view a bridge, and the prompter the same bridge:

```swift
import ReviewSwiftUI

@State private var bridge = ReviewRequestBridge()

var body: some View {
    RootView().reviewRequests(bridge, suppressed: isSheetPresented)
}

let prompter = ReviewPrompter(
    policy: policy,
    version: AppVersion(bundle: .main) ?? AppVersion(major: 0),
    store: UserDefaultsReviewStateStore(),
    asker: bridge
)
```

Record, and reach moments:

```swift
await prompter.markActive()                        // at launch and on return to the foreground
await prompter.record(.tripBooked, in: ReviewScope(trip.id))
await prompter.block(.paywallDismissed)
await prompter.reach(ReviewMoment(.afterJournal, in: ReviewScope(trip.id),
                                  ongoing: isOffline ? [.offline] : []))
```

A settings row the person presses themselves:

```swift
if let id = AppStoreID(appStoreID) {
    Link("Rate on the App Store", destination: WriteReviewLink.url(for: id))
}
```

## Documentation

[DESIGN.md](./DESIGN.md) covers the rules, their order, the state format, the reasons behind the
non-goals with citations, the analytics bridge, and how an app integrates it.

## Installation

```swift
.package(url: "https://github.com/no-problem-dev/swift-review.git", .upToNextMinor(from: "0.1.0"))
```

| Product | Contents | Depends on |
|---|---|---|
| `ReviewCore` | Vocabulary, decision, prompter, ports, stores, write-review link, feedback | Foundation |
| `ReviewSwiftUI` | `ReviewRequestBridge`, `.reviewRequests`, `MailFeedbackSender` | SwiftUI, StoreKit |
| `ReviewTesting` | Test doubles | nothing |

To send metrics to [swift-analytics](https://github.com/no-problem-dev/swift-analytics), map
`ReviewMetricEvent` onto an `AnalyticsEvent` in about twenty lines in your app (DESIGN.md §8).
Bundling that adapter here would add a dependency to every consumer.

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## License

MIT — see [LICENSE](LICENSE).
