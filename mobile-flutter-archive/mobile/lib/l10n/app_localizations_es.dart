// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'Cargando...';

  @override
  String get error => 'Algo salió mal';

  @override
  String get retry => 'Reintentar';

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get done => 'Listo';

  @override
  String get delete => 'Eliminar';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get email => 'Correo electrónico';

  @override
  String get password => 'Contraseña';

  @override
  String get serverUrl => 'URL del servidor';

  @override
  String get connectToServer => 'Conecta con tu servidor';

  @override
  String get scanQr => 'Escanear QR';

  @override
  String get enterCode => 'Ingresar código';

  @override
  String get directUrl => 'URL directa';

  @override
  String get pointCameraAtQr =>
      'Apunta la cámara al código QR que muestra nclaw.';

  @override
  String get codeScanned => 'Código escaneado';

  @override
  String get connectionFailed =>
      'Conexión fallida. Verifica la URL del servidor.';

  @override
  String get signInFailed =>
      'Error al iniciar sesión. Verifica tu correo y contraseña.';

  @override
  String get enterServerCredentials =>
      'Ingresa la URL de tu servidor y tus credenciales.';

  @override
  String get serverName => 'Nombre del servidor (opcional)';

  @override
  String get serverNameHint => 'Mi servidor';

  @override
  String get pairingCode => 'Código de emparejamiento';

  @override
  String get enterPairingCode =>
      'Ingresa el código mostrado por nclaw o enviado por tu bot de Telegram.';

  @override
  String get codeVerified =>
      'Código verificado. Ingresa tu contraseña para completar el inicio de sesión.';

  @override
  String get topics => 'Temas';

  @override
  String get memories => 'Recuerdos';

  @override
  String get chat => 'Chat';

  @override
  String get settings => 'Configuración';

  @override
  String get newConversation => 'Nueva conversación';

  @override
  String get searchMemories => 'Buscar recuerdos...';

  @override
  String get noMemories => 'Sin recuerdos aún. Inicia una conversación.';

  @override
  String get noTopics => 'Sin temas aún.';

  @override
  String get addServer => 'Agregar servidor';

  @override
  String get manageApiKeys => 'Gestionar claves API';

  @override
  String get voiceConversation => 'Conversación de voz';

  @override
  String get quickCapture => 'Captura rápida';

  @override
  String get feedback => 'Comentarios';

  @override
  String get usage => 'Uso';
}
