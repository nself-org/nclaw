// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'ɳClaw';

  @override
  String get loading => 'جارٍ التحميل...';

  @override
  String get error => 'حدث خطأ ما';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get cancel => 'إلغاء';

  @override
  String get save => 'حفظ';

  @override
  String get done => 'تم';

  @override
  String get delete => 'حذف';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get password => 'كلمة المرور';

  @override
  String get serverUrl => 'عنوان URL للخادم';

  @override
  String get connectToServer => 'الاتصال بخادمك';

  @override
  String get scanQr => 'مسح رمز QR';

  @override
  String get enterCode => 'إدخال الرمز';

  @override
  String get directUrl => 'URL مباشر';

  @override
  String get pointCameraAtQr =>
      'وجّه الكاميرا نحو رمز QR المعروض بواسطة nclaw.';

  @override
  String get codeScanned => 'تم مسح الرمز';

  @override
  String get connectionFailed => 'فشل الاتصال. تحقق من عنوان URL للخادم.';

  @override
  String get signInFailed =>
      'فشل تسجيل الدخول. تحقق من البريد الإلكتروني وكلمة المرور.';

  @override
  String get enterServerCredentials =>
      'أدخل عنوان URL للخادم وبيانات اعتماد حسابك.';

  @override
  String get serverName => 'اسم الخادم (اختياري)';

  @override
  String get serverNameHint => 'خادمي';

  @override
  String get pairingCode => 'رمز الاقتران';

  @override
  String get enterPairingCode =>
      'أدخل الرمز المعروض بواسطة nclaw أو المُرسَل عبر بوت Telegram.';

  @override
  String get codeVerified =>
      'تم التحقق من الرمز. أدخل كلمة المرور لإكمال تسجيل الدخول.';

  @override
  String get topics => 'المواضيع';

  @override
  String get memories => 'الذكريات';

  @override
  String get chat => 'الدردشة';

  @override
  String get settings => 'الإعدادات';

  @override
  String get newConversation => 'محادثة جديدة';

  @override
  String get searchMemories => 'البحث في الذكريات...';

  @override
  String get noMemories => 'لا توجد ذكريات بعد. ابدأ محادثة.';

  @override
  String get noTopics => 'لا توجد مواضيع بعد.';

  @override
  String get addServer => 'إضافة خادم';

  @override
  String get manageApiKeys => 'إدارة مفاتيح API';

  @override
  String get voiceConversation => 'محادثة صوتية';

  @override
  String get quickCapture => 'التقاط سريع';

  @override
  String get feedback => 'تعليقات';

  @override
  String get usage => 'الاستخدام';
}
