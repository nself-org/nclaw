// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => '加载中...';

  @override
  String get error => '出现了问题';

  @override
  String get retry => '重试';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get done => '完成';

  @override
  String get delete => '删除';

  @override
  String get signIn => '登录';

  @override
  String get signOut => '退出登录';

  @override
  String get email => '电子邮件';

  @override
  String get password => '密码';

  @override
  String get serverUrl => '服务器URL';

  @override
  String get connectToServer => '连接到您的服务器';

  @override
  String get scanQr => '扫描二维码';

  @override
  String get enterCode => '输入代码';

  @override
  String get directUrl => '直接URL';

  @override
  String get pointCameraAtQr => '将相机对准nclaw显示的二维码。';

  @override
  String get codeScanned => '二维码已扫描';

  @override
  String get connectionFailed => '连接失败。请检查服务器URL。';

  @override
  String get signInFailed => '登录失败。请检查您的电子邮件和密码。';

  @override
  String get enterServerCredentials => '输入您的服务器URL和账号凭据。';

  @override
  String get serverName => '服务器名称（可选）';

  @override
  String get serverNameHint => '我的服务器';

  @override
  String get pairingCode => '配对码';

  @override
  String get enterPairingCode => '输入nclaw显示的代码或通过Telegram机器人发送的代码。';

  @override
  String get codeVerified => '代码已验证。请输入密码以完成登录。';

  @override
  String get topics => '话题';

  @override
  String get memories => '记忆';

  @override
  String get chat => '聊天';

  @override
  String get settings => '设置';

  @override
  String get newConversation => '新对话';

  @override
  String get searchMemories => '搜索记忆...';

  @override
  String get noMemories => '还没有记忆。开始一段对话吧。';

  @override
  String get noTopics => '还没有话题。';

  @override
  String get addServer => '添加服务器';

  @override
  String get manageApiKeys => '管理API密钥';

  @override
  String get voiceConversation => '语音对话';

  @override
  String get quickCapture => '快速捕获';

  @override
  String get feedback => '反馈';

  @override
  String get usage => '用量';
}
