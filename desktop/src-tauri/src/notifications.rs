//! T-2085: Native system notifications from server commands.

/// Show a native OS notification.
pub fn show_notification(title: &str, body: &str) {
    if let Err(e) = notify_rust::Notification::new()
        .summary(title)
        .body(body)
        .appname("nSelf Companion")
        .show()
    {
        tracing::warn!(error = %e, "Failed to show notification");
    }
}
