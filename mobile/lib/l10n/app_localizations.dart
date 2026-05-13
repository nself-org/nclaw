import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// The name of the application
  ///
  /// In en, this message translates to:
  /// **'ɳClaw'**
  String get appTitle;

  /// Generic loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Generic error message
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get error;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Sign in button label
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// Sign out button label
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// Email field label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Server URL field label
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// Pairing screen headline
  ///
  /// In en, this message translates to:
  /// **'Connect to your server'**
  String get connectToServer;

  /// QR scan tab label
  ///
  /// In en, this message translates to:
  /// **'Scan QR'**
  String get scanQr;

  /// Code entry tab label
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get enterCode;

  /// Direct URL tab label
  ///
  /// In en, this message translates to:
  /// **'Direct URL'**
  String get directUrl;

  /// QR scan instruction
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the QR code shown by nclaw.'**
  String get pointCameraAtQr;

  /// Success message after QR scan
  ///
  /// In en, this message translates to:
  /// **'Code scanned'**
  String get codeScanned;

  /// Connection error message
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check the server URL.'**
  String get connectionFailed;

  /// Sign-in error message
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. Check your email and password.'**
  String get signInFailed;

  /// Direct URL tab description
  ///
  /// In en, this message translates to:
  /// **'Enter your server URL and account credentials.'**
  String get enterServerCredentials;

  /// Server name field label
  ///
  /// In en, this message translates to:
  /// **'Server name (optional)'**
  String get serverName;

  /// Server name field hint
  ///
  /// In en, this message translates to:
  /// **'My Server'**
  String get serverNameHint;

  /// Pairing code field label
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCode;

  /// Pairing code tab description
  ///
  /// In en, this message translates to:
  /// **'Enter the code shown by nclaw or sent via your Telegram bot.'**
  String get enterPairingCode;

  /// Code verification success message
  ///
  /// In en, this message translates to:
  /// **'Code verified! Enter your password to complete sign-in.'**
  String get codeVerified;

  /// Topics navigation label
  ///
  /// In en, this message translates to:
  /// **'Topics'**
  String get topics;

  /// Memories navigation label
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get memories;

  /// Chat navigation label
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// Settings navigation label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Button to start a new conversation
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get newConversation;

  /// Search field hint in memories screen
  ///
  /// In en, this message translates to:
  /// **'Search memories...'**
  String get searchMemories;

  /// Empty state for memories screen
  ///
  /// In en, this message translates to:
  /// **'No memories yet. Start a conversation.'**
  String get noMemories;

  /// Empty state for topics screen
  ///
  /// In en, this message translates to:
  /// **'No topics yet.'**
  String get noTopics;

  /// Add server button label
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get addServer;

  /// API keys screen title
  ///
  /// In en, this message translates to:
  /// **'Manage API keys'**
  String get manageApiKeys;

  /// Voice conversation screen title
  ///
  /// In en, this message translates to:
  /// **'Voice conversation'**
  String get voiceConversation;

  /// Quick capture screen title
  ///
  /// In en, this message translates to:
  /// **'Quick capture'**
  String get quickCapture;

  /// Feedback screen title
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// Usage screen title
  ///
  /// In en, this message translates to:
  /// **'Usage'**
  String get usage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
