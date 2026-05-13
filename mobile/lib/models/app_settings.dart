/// Application settings model for the 10-tab settings screen (E-26-04).
class AppSettings {
  // General
  final String displayName;
  // S21-T11: Profile bio + avatar URL.
  final String bio;
  final String avatarUrl;
  final String language;
  final bool launchAtLogin;

  // Model
  final String defaultModel;
  final double temperature;
  final int maxTokens;

  // Appearance
  final String theme; // 'system', 'dark', 'light'
  final double fontSize;
  final bool compactMode;

  // Notifications
  final bool pushEnabled;
  final bool soundEnabled;
  final bool badgeEnabled;
  final bool digestEnabled;
  final String digestFrequency; // 'daily', 'weekly', 'never'

  // Privacy
  final bool biometricLock;
  final bool analyticsEnabled;
  final int autoLockMinutes;

  // Data
  final bool offlineModeEnabled;
  final int cacheSizeMb;
  final bool autoSync;
  final int syncIntervalMinutes;

  // Sharing
  final String defaultShareTopic;
  final bool shareSheetEnabled;

  // API Keys
  final Map<String, String> apiKeys;

  // Billing
  final String? subscriptionTier;
  final DateTime? subscriptionExpiry;

  // Advanced
  final bool debugMode;
  final String? customEndpoint;
  final bool experimentalFeatures;

  const AppSettings({
    this.displayName = '',
    this.bio = '',
    this.avatarUrl = '',
    this.language = 'en',
    this.launchAtLogin = false,
    this.defaultModel = 'auto',
    this.temperature = 0.7,
    this.maxTokens = 4096,
    this.theme = 'system',
    this.fontSize = 14.0,
    this.compactMode = false,
    this.pushEnabled = true,
    this.soundEnabled = true,
    this.badgeEnabled = true,
    this.digestEnabled = true,
    this.digestFrequency = 'daily',
    this.biometricLock = false,
    this.analyticsEnabled = false,
    this.autoLockMinutes = 5,
    this.offlineModeEnabled = true,
    this.cacheSizeMb = 100,
    this.autoSync = true,
    this.syncIntervalMinutes = 15,
    this.defaultShareTopic = '',
    this.shareSheetEnabled = true,
    this.apiKeys = const {},
    this.subscriptionTier,
    this.subscriptionExpiry,
    this.debugMode = false,
    this.customEndpoint,
    this.experimentalFeatures = false,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        displayName: json['display_name'] as String? ?? '',
        bio: json['bio'] as String? ?? '',
        avatarUrl: json['avatar_url'] as String? ?? '',
        language: json['language'] as String? ?? 'en',
        launchAtLogin: json['launch_at_login'] as bool? ?? false,
        defaultModel: json['default_model'] as String? ?? 'auto',
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
        maxTokens: (json['max_tokens'] as num?)?.toInt() ?? 4096,
        theme: json['theme'] as String? ?? 'system',
        fontSize: (json['font_size'] as num?)?.toDouble() ?? 14.0,
        compactMode: json['compact_mode'] as bool? ?? false,
        pushEnabled: json['push_enabled'] as bool? ?? true,
        soundEnabled: json['sound_enabled'] as bool? ?? true,
        badgeEnabled: json['badge_enabled'] as bool? ?? true,
        digestEnabled: json['digest_enabled'] as bool? ?? true,
        digestFrequency: json['digest_frequency'] as String? ?? 'daily',
        biometricLock: json['biometric_lock'] as bool? ?? false,
        analyticsEnabled: json['analytics_enabled'] as bool? ?? false,
        autoLockMinutes: (json['auto_lock_minutes'] as num?)?.toInt() ?? 5,
        offlineModeEnabled: json['offline_mode_enabled'] as bool? ?? true,
        cacheSizeMb: (json['cache_size_mb'] as num?)?.toInt() ?? 100,
        autoSync: json['auto_sync'] as bool? ?? true,
        syncIntervalMinutes:
            (json['sync_interval_minutes'] as num?)?.toInt() ?? 15,
        defaultShareTopic: json['default_share_topic'] as String? ?? '',
        shareSheetEnabled: json['share_sheet_enabled'] as bool? ?? true,
        apiKeys: (json['api_keys'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            const {},
        subscriptionTier: json['subscription_tier'] as String?,
        subscriptionExpiry: json['subscription_expiry'] != null
            ? DateTime.tryParse(json['subscription_expiry'] as String)
            : null,
        debugMode: json['debug_mode'] as bool? ?? false,
        customEndpoint: json['custom_endpoint'] as String?,
        experimentalFeatures:
            json['experimental_features'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'display_name': displayName,
        'bio': bio,
        'avatar_url': avatarUrl,
        'language': language,
        'launch_at_login': launchAtLogin,
        'default_model': defaultModel,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'theme': theme,
        'font_size': fontSize,
        'compact_mode': compactMode,
        'push_enabled': pushEnabled,
        'sound_enabled': soundEnabled,
        'badge_enabled': badgeEnabled,
        'digest_enabled': digestEnabled,
        'digest_frequency': digestFrequency,
        'biometric_lock': biometricLock,
        'analytics_enabled': analyticsEnabled,
        'auto_lock_minutes': autoLockMinutes,
        'offline_mode_enabled': offlineModeEnabled,
        'cache_size_mb': cacheSizeMb,
        'auto_sync': autoSync,
        'sync_interval_minutes': syncIntervalMinutes,
        'default_share_topic': defaultShareTopic,
        'share_sheet_enabled': shareSheetEnabled,
        'api_keys': apiKeys,
        'subscription_tier': subscriptionTier,
        'subscription_expiry': subscriptionExpiry?.toIso8601String(),
        'debug_mode': debugMode,
        'custom_endpoint': customEndpoint,
        'experimental_features': experimentalFeatures,
      };

  AppSettings copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? language,
    bool? launchAtLogin,
    String? defaultModel,
    double? temperature,
    int? maxTokens,
    String? theme,
    double? fontSize,
    bool? compactMode,
    bool? pushEnabled,
    bool? soundEnabled,
    bool? badgeEnabled,
    bool? digestEnabled,
    String? digestFrequency,
    bool? biometricLock,
    bool? analyticsEnabled,
    int? autoLockMinutes,
    bool? offlineModeEnabled,
    int? cacheSizeMb,
    bool? autoSync,
    int? syncIntervalMinutes,
    String? defaultShareTopic,
    bool? shareSheetEnabled,
    Map<String, String>? apiKeys,
    String? subscriptionTier,
    DateTime? subscriptionExpiry,
    bool? debugMode,
    String? customEndpoint,
    bool? experimentalFeatures,
  }) =>
      AppSettings(
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        language: language ?? this.language,
        launchAtLogin: launchAtLogin ?? this.launchAtLogin,
        defaultModel: defaultModel ?? this.defaultModel,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
        theme: theme ?? this.theme,
        fontSize: fontSize ?? this.fontSize,
        compactMode: compactMode ?? this.compactMode,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        badgeEnabled: badgeEnabled ?? this.badgeEnabled,
        digestEnabled: digestEnabled ?? this.digestEnabled,
        digestFrequency: digestFrequency ?? this.digestFrequency,
        biometricLock: biometricLock ?? this.biometricLock,
        analyticsEnabled: analyticsEnabled ?? this.analyticsEnabled,
        autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
        offlineModeEnabled: offlineModeEnabled ?? this.offlineModeEnabled,
        cacheSizeMb: cacheSizeMb ?? this.cacheSizeMb,
        autoSync: autoSync ?? this.autoSync,
        syncIntervalMinutes:
            syncIntervalMinutes ?? this.syncIntervalMinutes,
        defaultShareTopic: defaultShareTopic ?? this.defaultShareTopic,
        shareSheetEnabled: shareSheetEnabled ?? this.shareSheetEnabled,
        apiKeys: apiKeys ?? this.apiKeys,
        subscriptionTier: subscriptionTier ?? this.subscriptionTier,
        subscriptionExpiry: subscriptionExpiry ?? this.subscriptionExpiry,
        debugMode: debugMode ?? this.debugMode,
        customEndpoint: customEndpoint ?? this.customEndpoint,
        experimentalFeatures:
            experimentalFeatures ?? this.experimentalFeatures,
      );
}
