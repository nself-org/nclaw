// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => '読み込み中...';

  @override
  String get error => 'エラーが発生しました';

  @override
  String get retry => '再試行';

  @override
  String get cancel => 'キャンセル';

  @override
  String get save => '保存';

  @override
  String get done => '完了';

  @override
  String get delete => '削除';

  @override
  String get signIn => 'サインイン';

  @override
  String get signOut => 'サインアウト';

  @override
  String get email => 'メールアドレス';

  @override
  String get password => 'パスワード';

  @override
  String get serverUrl => 'サーバーURL';

  @override
  String get connectToServer => 'サーバーに接続する';

  @override
  String get scanQr => 'QRをスキャン';

  @override
  String get enterCode => 'コードを入力';

  @override
  String get directUrl => '直接URL';

  @override
  String get pointCameraAtQr => 'nclawに表示されているQRコードにカメラを向けてください。';

  @override
  String get codeScanned => 'コードをスキャンしました';

  @override
  String get connectionFailed => '接続に失敗しました。サーバーURLを確認してください。';

  @override
  String get signInFailed => 'サインインに失敗しました。メールアドレスとパスワードを確認してください。';

  @override
  String get enterServerCredentials => 'サーバーのURLとアカウント情報を入力してください。';

  @override
  String get serverName => 'サーバー名（任意）';

  @override
  String get serverNameHint => 'マイサーバー';

  @override
  String get pairingCode => 'ペアリングコード';

  @override
  String get enterPairingCode =>
      'nclawに表示されたコード、またはTelegramボットから送られたコードを入力してください。';

  @override
  String get codeVerified => 'コードが確認されました。サインインを完了するためにパスワードを入力してください。';

  @override
  String get topics => 'トピック';

  @override
  String get memories => 'メモリー';

  @override
  String get chat => 'チャット';

  @override
  String get settings => '設定';

  @override
  String get newConversation => '新しい会話';

  @override
  String get searchMemories => 'メモリーを検索...';

  @override
  String get noMemories => 'まだメモリーがありません。会話を始めてください。';

  @override
  String get noTopics => 'まだトピックがありません。';

  @override
  String get addServer => 'サーバーを追加';

  @override
  String get manageApiKeys => 'APIキーを管理';

  @override
  String get voiceConversation => '音声会話';

  @override
  String get quickCapture => 'クイックキャプチャ';

  @override
  String get feedback => 'フィードバック';

  @override
  String get usage => '使用状況';
}
