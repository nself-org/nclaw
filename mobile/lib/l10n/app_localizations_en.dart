// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'Loading...';

  @override
  String get error => 'Something went wrong';

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get done => 'Done';

  @override
  String get delete => 'Delete';

  @override
  String get signIn => 'Sign In';

  @override
  String get signOut => 'Sign Out';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get serverUrl => 'Server URL';

  @override
  String get connectToServer => 'Connect to your server';

  @override
  String get scanQr => 'Scan QR';

  @override
  String get enterCode => 'Enter Code';

  @override
  String get directUrl => 'Direct URL';

  @override
  String get pointCameraAtQr =>
      'Point your camera at the QR code shown by nclaw.';

  @override
  String get codeScanned => 'Code scanned';

  @override
  String get connectionFailed => 'Connection failed. Check the server URL.';

  @override
  String get signInFailed => 'Sign-in failed. Check your email and password.';

  @override
  String get enterServerCredentials =>
      'Enter your server URL and account credentials.';

  @override
  String get serverName => 'Server name (optional)';

  @override
  String get serverNameHint => 'My Server';

  @override
  String get pairingCode => 'Pairing code';

  @override
  String get enterPairingCode =>
      'Enter the code shown by nclaw or sent via your Telegram bot.';

  @override
  String get codeVerified =>
      'Code verified! Enter your password to complete sign-in.';

  @override
  String get topics => 'Topics';

  @override
  String get memories => 'Memories';

  @override
  String get chat => 'Chat';

  @override
  String get settings => 'Settings';

  @override
  String get newConversation => 'New conversation';

  @override
  String get searchMemories => 'Search memories...';

  @override
  String get noMemories => 'No memories yet. Start a conversation.';

  @override
  String get noTopics => 'No topics yet.';

  @override
  String get addServer => 'Add Server';

  @override
  String get manageApiKeys => 'Manage API keys';

  @override
  String get voiceConversation => 'Voice conversation';

  @override
  String get quickCapture => 'Quick capture';

  @override
  String get feedback => 'Feedback';

  @override
  String get usage => 'Usage';
}
