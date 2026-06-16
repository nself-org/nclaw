import Flutter
import UIKit
import UserNotifications
import FirebaseMessaging

// S22-T03: APNs registration + Notification Service Extension handoff.
//
// Registers the app with Apple Push Notification service so Firebase
// Messaging (FCM) can deliver push notifications on iOS. FCM requires
// a valid APNs token; without registerForRemoteNotifications() the
// FCM token never resolves on real devices.
//
// S15-T18: Mobile FFI damper wiring.
//
// Notifies the Rust libnclaw core of iOS Low Power Mode changes via the
// nclaw_set_low_power() C-ABI export. The core adjusts the tier classifier
// and inference streaming behaviour accordingly.
// The libnclaw.xcframework is linked via mobile/ios/libnclaw.xcframework;
// bridging header declares nclaw_set_low_power(Bool).

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Set the notification delegate so foreground notifications display a banner
    // even while the app is active. Firebase installs its own delegate on top
    // of this; setting the default here is safe and idempotent.
    UNUserNotificationCenter.current().delegate = self

    // Request APNs registration. The actual permission prompt is still driven
    // by Firebase / flutter_local_notifications at a more user-friendly moment;
    // this call is what makes iOS hand the device an APNs device token.
    application.registerForRemoteNotifications()

    // S15-T18: Send initial Low Power Mode state to Rust core on launch so
    // the tier classifier has an accurate reading before the first inference.
    syncLowPowerMode()

    // S15-T18: Observe future Low Power Mode toggle events for the lifetime of
    // the app. The notification fires on the main thread (iOS contract).
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(powerStateDidChange),
      name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    // Re-sync on foreground: the user may have toggled Low Power Mode while the
    // app was in the background where NSProcessInfoPowerStateDidChange does not
    // reliably fire.
    syncLowPowerMode()
    super.applicationDidBecomeActive(application)
  }

  // MARK: — Low Power Mode helpers (S15-T18)

  /// Read current Low Power Mode state from ProcessInfo and forward to libnclaw.
  private func syncLowPowerMode() {
    let isLow = ProcessInfo.processInfo.isLowPowerModeEnabled
    nclaw_set_low_power(isLow)
  }

  /// Called by NotificationCenter when iOS Low Power Mode is toggled.
  @objc private func powerStateDidChange(_ notification: Notification) {
    syncLowPowerMode()
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Hand the APNs token to Firebase Messaging. FCM converts the APNs token
    // into an FCM registration token which the Dart side then sends to the
    // backend `/claw/devices/register` endpoint.
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    NSLog("[nclaw] APNs registration failed: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
