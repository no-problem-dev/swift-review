// The names every app shares. Each one matches a rule in studio `knowledge/rating.md` or a value in
// the common analytics catalog (`swift-analytics` `Schema/common/common.yaml`), so all apps record
// and report them the same way. Apps still declare their own signals and moments next to these.

extension ReviewMomentName {
    /// Right after the person closed the in-app "What's New" for a new version.
    ///
    /// Use it with either kind of moment: ``ReviewMoment`` to call the system prompt, or
    /// ``ReviewScreenMoment`` to show the app's own review screen (rating.md R24). The raw value is
    /// the common catalog's `review_requested.moment` value `after_whats_new`.
    public static let afterWhatsNew: Self = "after_whats_new"
}

extension ReviewBlockerKind {
    /// The paywall was closed without buying. Held back 14 days by default (rating.md R10, R25).
    public static let paywallDismissed: Self = "paywall_dismissed"
    /// An error or a failed sync was shown. Held back 3 days by default (R10, R25).
    public static let error: Self = "error"
    /// The person sent feedback. Held back 30 days by default (R25).
    public static let feedbackSent: Self = "feedback_sent"
    /// The person opened the screen that explains how to cancel. Held back 90 days by default (R25).
    public static let cancelScreenOpened: Self = "cancel_screen_opened"
    /// A purchase finished in this launch. Pass it in ``ReviewMoment/ongoing`` for the rest of the
    /// launch; it has no default cooldown (R10: "not in a launch that bought").
    public static let purchased: Self = "purchased"
    /// The paywall was shown in this launch. Pass it in ``ReviewMoment/ongoing`` for the rest of the
    /// launch (R10: "not in a launch that showed the paywall").
    public static let paywallShown: Self = "paywall_shown"
}
