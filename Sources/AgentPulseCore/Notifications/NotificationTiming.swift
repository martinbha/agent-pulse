import Foundation

/// Shared timing for the transient-notification lifecycle, used by both the
/// main app's fallback poster and the notifier helpers. Ordering constraints:
/// `staleSweepAge` must exceed `bannerDismissalDelay` so a sweep never removes
/// a notification whose banner may still be visible, and a posting helper must
/// outlive `bannerDismissalDelay` to run its own cleanup.
public enum NotificationTiming {
    /// Banners hide on their own after ~5 s; removing the delivered
    /// notification after this delay keeps Notification Center empty without
    /// cutting the banner short.
    public static let bannerDismissalDelay: TimeInterval = 8

    /// Extra lifetime a posting helper gets after removal so the request
    /// reaches the notification server before the process exits.
    public static let posterExitGrace: TimeInterval = 1

    /// How long a click-launched helper waits for its notification response
    /// before giving up and exiting.
    public static let interactionDeadline: TimeInterval = 5

    /// Hard ceiling on a posting helper's lifetime. Covers an unanswered
    /// first-run permission prompt, which can otherwise hold the process open
    /// for minutes.
    public static let posterDeadline: TimeInterval = 120

    /// Delivered notifications older than this are strays from a poster that
    /// died before its cleanup ran.
    public static let staleSweepAge: TimeInterval = 15
}
