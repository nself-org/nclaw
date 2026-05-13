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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
