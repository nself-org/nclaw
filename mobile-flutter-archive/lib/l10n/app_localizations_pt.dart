// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'A carregar...';

  @override
  String get error => 'Algo correu mal';

  @override
  String get retry => 'Tentar novamente';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get done => 'Concluído';

  @override
  String get delete => 'Eliminar';

  @override
  String get signIn => 'Iniciar sessão';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Palavra-passe';

  @override
  String get serverUrl => 'URL do servidor';

  @override
  String get connectToServer => 'Ligue-se ao seu servidor';

  @override
  String get scanQr => 'Ler QR';

  @override
  String get enterCode => 'Inserir código';

  @override
  String get directUrl => 'URL direto';

  @override
  String get pointCameraAtQr =>
      'Aponte a câmara para o código QR mostrado pelo nclaw.';

  @override
  String get codeScanned => 'Código lido';

  @override
  String get connectionFailed =>
      'Falha na ligação. Verifique o URL do servidor.';

  @override
  String get signInFailed =>
      'Falha ao iniciar sessão. Verifique o e-mail e a palavra-passe.';

  @override
  String get enterServerCredentials =>
      'Insira o URL do servidor e as suas credenciais.';

  @override
  String get serverName => 'Nome do servidor (opcional)';

  @override
  String get serverNameHint => 'O meu servidor';

  @override
  String get pairingCode => 'Código de emparelhamento';

  @override
  String get enterPairingCode =>
      'Insira o código mostrado pelo nclaw ou enviado através do bot do Telegram.';

  @override
  String get codeVerified =>
      'Código verificado. Insira a palavra-passe para concluir o início de sessão.';

  @override
  String get topics => 'Tópicos';

  @override
  String get memories => 'Memórias';

  @override
  String get chat => 'Conversa';

  @override
  String get settings => 'Definições';

  @override
  String get newConversation => 'Nova conversa';

  @override
  String get searchMemories => 'Pesquisar memórias...';

  @override
  String get noMemories => 'Ainda sem memórias. Inicie uma conversa.';

  @override
  String get noTopics => 'Ainda sem tópicos.';

  @override
  String get addServer => 'Adicionar servidor';

  @override
  String get manageApiKeys => 'Gerir chaves de API';

  @override
  String get voiceConversation => 'Conversa por voz';

  @override
  String get quickCapture => 'Captura rápida';

  @override
  String get feedback => 'Comentários';

  @override
  String get usage => 'Utilização';
}
