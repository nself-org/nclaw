// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'Laden...';

  @override
  String get error => 'Etwas ist schiefgelaufen';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get done => 'Fertig';

  @override
  String get delete => 'Löschen';

  @override
  String get signIn => 'Anmelden';

  @override
  String get signOut => 'Abmelden';

  @override
  String get email => 'E-Mail-Adresse';

  @override
  String get password => 'Passwort';

  @override
  String get serverUrl => 'Server-URL';

  @override
  String get connectToServer => 'Mit deinem Server verbinden';

  @override
  String get scanQr => 'QR scannen';

  @override
  String get enterCode => 'Code eingeben';

  @override
  String get directUrl => 'Direkte URL';

  @override
  String get pointCameraAtQr =>
      'Richte deine Kamera auf den von nclaw angezeigten QR-Code.';

  @override
  String get codeScanned => 'Code gescannt';

  @override
  String get connectionFailed =>
      'Verbindung fehlgeschlagen. Überprüfe die Server-URL.';

  @override
  String get signInFailed =>
      'Anmeldung fehlgeschlagen. Überprüfe E-Mail und Passwort.';

  @override
  String get enterServerCredentials =>
      'Gib deine Server-URL und Anmeldedaten ein.';

  @override
  String get serverName => 'Servername (optional)';

  @override
  String get serverNameHint => 'Mein Server';

  @override
  String get pairingCode => 'Kopplungscode';

  @override
  String get enterPairingCode =>
      'Gib den von nclaw angezeigten oder per Telegram-Bot gesendeten Code ein.';

  @override
  String get codeVerified =>
      'Code verifiziert. Gib dein Passwort ein, um die Anmeldung abzuschließen.';

  @override
  String get topics => 'Themen';

  @override
  String get memories => 'Erinnerungen';

  @override
  String get chat => 'Chat';

  @override
  String get settings => 'Einstellungen';

  @override
  String get newConversation => 'Neues Gespräch';

  @override
  String get searchMemories => 'Erinnerungen suchen...';

  @override
  String get noMemories => 'Noch keine Erinnerungen. Starte ein Gespräch.';

  @override
  String get noTopics => 'Noch keine Themen.';

  @override
  String get addServer => 'Server hinzufügen';

  @override
  String get manageApiKeys => 'API-Schlüssel verwalten';

  @override
  String get voiceConversation => 'Sprachgespräch';

  @override
  String get quickCapture => 'Schnellaufnahme';

  @override
  String get feedback => 'Feedback';

  @override
  String get usage => 'Nutzung';
}
