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
- **Thresholds as values, with one set of defaults.** The defaults are studio's rating rules: 7 days
  after install, once per version, 60 days apart, 3 a year, 30 seconds into the launch, the third
  good outcome, quiet after a paywall (14 days), an error (3), feedback (30) and the cancel screen (90).
  Pass your moments; override a value only with a reason
- **Two kinds of moment.** `ReviewMoment` calls the system prompt. `ReviewScreenMoment` decides
  whether your own review screen may appear (after What's New, say): it never reaches the system,
  so only once-per-version, the days since install, blockers and a wait after "rated" apply
- **`AppVersion`.** The one version type for the family: parse, compare, print
- **A metrics hook.** A protocol or a closure; `review_requested { moment }` matches the common
  analytics catalog
- **Every call counts.** The system never says whether it showed a prompt, so calls are counted,
  shown or not; a request the screen dropped before calling is not
- **Device-only, versioned state.** JSON with a schema number; a newer schema is never overwritten,
  unknown fields survive, account deletion resets it
- **Feedback, separately.** A draft with opt-in diagnostics (what you preview is what is sent), a
  mail composer (one attachment, `mailto:` as the fallback) and an HTTP channel over your own transport
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
    static let offline: Self = "offline"   // paywallDismissed, error, … are built in
}

let policy = ReviewPolicy(
    moments: [.afterJournal: ReviewMomentRule()],     // the third good outcome
    screens: [.afterWhatsNew: ReviewScreenRule()]     // optional: your own screen
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
    asker: bridge,
    metrics: ReviewMetricsHandler { event in
        guard event.isInCommonCatalog else { return }   // review_requested { moment }
        analytics.track(name: event.name, parameters: event.parameters)
    }
)
```

Record, and reach moments:

```swift
await prompter.markActive()                        // at launch and on return to the foreground
await prompter.record(.tripBooked, in: ReviewScope(trip.id))
await prompter.block(.paywallDismissed)
await prompter.reach(ReviewMoment(.afterJournal, in: ReviewScope(trip.id),
                                  ongoing: isOffline ? [.offline] : []))

// Your own screen after What's New: the system is never called.
if await prompter.present(ReviewScreenMoment(.afterWhatsNew)) == .ask { showReviewScreen = true }
await prompter.markRated()                         // when its rate button is pressed
```

A settings row the person presses themselves:

```swift
if let id = AppStoreID(appStoreID) {
    Link("Rate on the App Store", destination: WriteReviewLink.url(for: id))
}
```

## Moving an app's own code onto this package

1. Depend on `.upToNextMinor(from: "0.2.0")`, delete your own `AppVersion` and use `ReviewCore`'s
2. Write `ReviewPolicy(moments: …)` with your moment and nothing else; keep a value only if you can
   say why (tabisaki keeps 3 days of use, 120 days and once per trip)
3. Replace your gate: the good outcome → `record`, paywall closed / error → `block(.paywallDismissed)` /
   `block(.error)`, the moment → `reach`. A settings button that called `requestReview` becomes
   `WriteReviewLink` (R7)
4. An own review screen after What's New (gamification-app's `ReviewAskGate`, reading-memory's
   `ReviewMoment.screenIsDue`) → `present(ReviewScreenMoment(.afterWhatsNew))` and `markRated()`.
   An app's own condition (such as "has received what the app promises") goes in `unmet:`, not
   `ongoing:`
5. Carry the old record over once: build a `ReviewState(installedAt:asks:ratedAt:)` from your old
   keys and `save` it through the store, so nobody is asked twice in the same version or waits 7
   days again. If only the first use is known (such as the oldest record's date),
   `backdateInstall(to:)` is enough for the 7 days, which the own screen also waits
6. Rename your `review_requested` (or `review_prompt_requested`) event to the catalog's
   `review_requested { moment }`

## Documentation

[DESIGN.md](./DESIGN.md) covers the rules, their order, the state format, the reasons behind the
non-goals with citations, the analytics bridge, and how an app integrates it.

## Installation

```swift
.package(url: "https://github.com/no-problem-dev/swift-review.git", .upToNextMinor(from: "0.2.0"))
```

| Product | Contents | Depends on |
|---|---|---|
| `ReviewCore` | Vocabulary, decision, prompter, ports, stores, write-review link, feedback | Foundation |
| `ReviewSwiftUI` | `ReviewRequestBridge`, `.reviewRequests`, `MailFeedbackSender`, `MailComposerFeedbackSender` and `.feedbackMailComposer` (one attachment) | SwiftUI, StoreKit, MessageUI (iOS) |
| `ReviewTesting` | Test doubles | nothing |

To send metrics to [swift-analytics](https://github.com/no-problem-dev/swift-analytics), map
`ReviewMetricEvent` onto an `AnalyticsEvent` in about twenty lines in your app (DESIGN.md §8).
Bundling that adapter here would add a dependency to every consumer.

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.2+

## License

MIT — see [LICENSE](LICENSE).
