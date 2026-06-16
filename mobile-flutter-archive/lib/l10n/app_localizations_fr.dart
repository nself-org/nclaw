// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'Chargement...';

  @override
  String get error => 'Une erreur est survenue';

  @override
  String get retry => 'Réessayer';

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get done => 'Terminé';

  @override
  String get delete => 'Supprimer';

  @override
  String get signIn => 'Se connecter';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get email => 'Adresse e-mail';

  @override
  String get password => 'Mot de passe';

  @override
  String get serverUrl => 'URL du serveur';

  @override
  String get connectToServer => 'Connectez-vous à votre serveur';

  @override
  String get scanQr => 'Scanner QR';

  @override
  String get enterCode => 'Saisir le code';

  @override
  String get directUrl => 'URL directe';

  @override
  String get pointCameraAtQr =>
      'Pointez votre caméra sur le code QR affiché par nclaw.';

  @override
  String get codeScanned => 'Code scanné';

  @override
  String get connectionFailed =>
      'Connexion échouée. Vérifiez l\'URL du serveur.';

  @override
  String get signInFailed =>
      'Échec de connexion. Vérifiez votre adresse e-mail et votre mot de passe.';

  @override
  String get enterServerCredentials =>
      'Entrez l\'URL de votre serveur et vos identifiants.';

  @override
  String get serverName => 'Nom du serveur (optionnel)';

  @override
  String get serverNameHint => 'Mon serveur';

  @override
  String get pairingCode => 'Code de jumelage';

  @override
  String get enterPairingCode =>
      'Entrez le code affiché par nclaw ou envoyé via votre bot Telegram.';

  @override
  String get codeVerified =>
      'Code vérifié. Entrez votre mot de passe pour finaliser la connexion.';

  @override
  String get topics => 'Sujets';

  @override
  String get memories => 'Souvenirs';

  @override
  String get chat => 'Discussion';

  @override
  String get settings => 'Paramètres';

  @override
  String get newConversation => 'Nouvelle conversation';

  @override
  String get searchMemories => 'Rechercher des souvenirs...';

  @override
  String get noMemories =>
      'Aucun souvenir pour l\'instant. Démarrez une conversation.';

  @override
  String get noTopics => 'Aucun sujet pour l\'instant.';

  @override
  String get addServer => 'Ajouter un serveur';

  @override
  String get manageApiKeys => 'Gérer les clés API';

  @override
  String get voiceConversation => 'Conversation vocale';

  @override
  String get quickCapture => 'Capture rapide';

  @override
  String get feedback => 'Retour';

  @override
  String get usage => 'Utilisation';
}
