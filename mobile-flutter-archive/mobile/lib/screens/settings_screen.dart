/// E-26-04: Settings with 10 navigation sections.
///
/// Full-screen stack navigation. Adaptive: Material 3 on Android,
/// Cupertino on iOS via platform checks.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../providers/connection_provider.dart';
import '../providers/settings_provider.dart';
import '../models/app_settings.dart';
import '../services/beta_channel_service.dart';
import '../theme/brand_theme.dart';
import '../widgets/empty_state.dart';
import 'feedback_screen.dart';
import 'oauth_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // S21-T04: 8-group settings organization.
    // Groups, in order:
    //  1. Profile
    //  2. Appearance
    //  3. AI & Models
    //  4. Account & Billing
    //  5. Privacy & Security
    //  6. Notifications
    //  7. Data & Sync
    //  8. About & Help
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SettingsGroup(title: 'Profile', children: [
            _SettingsNavTile(
              icon: Icons.person_outline,
              title: 'Profile',
              subtitle: 'Display name, avatar, bio',
              onTap: () => _push(context, const _GeneralSettings()),
            ),
          ]),
          _SettingsGroup(title: 'Appearance', children: [
            _SettingsNavTile(
              icon: Icons.palette,
              title: 'Theme & layout',
              onTap: () => _push(context, const _AppearanceSettings()),
            ),
          ]),
          _SettingsGroup(title: 'AI & Models', children: [
            _SettingsNavTile(
              icon: Icons.smart_toy,
              title: 'Model',
              subtitle: 'Default model, Ollama, auto-select',
              onTap: () => _push(context, const _ModelSettings()),
            ),
            _SettingsNavTile(
              icon: Icons.vpn_key,
              title: 'API keys',
              subtitle: 'Provider credentials',
              onTap: () => _push(context, const _ApiKeysSettings()),
            ),
            _SettingsNavTile(
              icon: Icons.account_tree_outlined,
              title: 'Account pool',
              subtitle: 'Gemini accounts for free quota',
              onTap: () => _push(context, const _PoolManagementScreen()),
            ),
          ]),
          _SettingsGroup(title: 'Account & Billing', children: [
            _SettingsNavTile(
              icon: Icons.credit_card,
              title: 'Billing',
              subtitle: 'Plan, invoices',
              onTap: () => _push(context, const _BillingSettings()),
            ),
          ]),
          _SettingsGroup(title: 'Privacy & Security', children: [
            _SettingsNavTile(
              icon: Icons.lock,
              title: 'Privacy',
              onTap: () => _push(context, const _PrivacySettings()),
            ),
          ]),
          _SettingsGroup(title: 'Notifications', children: [
            _SettingsNavTile(
              icon: Icons.notifications,
              title: 'Notifications',
              onTap: () => _push(context, const _NotificationSettings()),
            ),
          ]),
          _SettingsGroup(title: 'Data & Sync', children: [
            _SettingsNavTile(
              icon: Icons.storage,
              title: 'Data',
              onTap: () => _push(context, const _DataSettings()),
            ),
            _SettingsNavTile(
              icon: Icons.share,
              title: 'Sharing',
              onTap: () => _push(context, const _SharingSettings()),
            ),
            _SettingsNavTile(
              icon: Icons.build,
              title: 'Advanced',
              onTap: () => _push(context, const _AdvancedSettings()),
            ),
          ]),
          _SettingsGroup(title: 'About & Help', children: [
            _SettingsNavTile(
              icon: Icons.feedback,
              title: 'Send feedback',
              onTap: () => _push(context, const FeedbackScreen()),
            ),
            _SettingsNavTile(
              icon: Icons.science,
              title: 'Beta program',
              onTap: () => _push(context, const _BetaProgramSettings()),
            ),
            _SettingsNavTile(
              icon: Icons.info_outline,
              title: 'About',
              onTap: () => _push(context, const _AboutSettings()),
            ),
          ]),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}

// -- Shared Components -------------------------------------------------------

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

// -- Sub-screens -------------------------------------------------------------

class _GeneralSettings extends ConsumerWidget {
  const _GeneralSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    // S21-T11: Profile screen with avatar + display name + bio.
    final initial = settings.displayName.isEmpty
        ? '?'
        : settings.displayName.characters.first.toUpperCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.2),
                    backgroundImage: settings.avatarUrl.isNotEmpty
                        ? NetworkImage(settings.avatarUrl)
                        : null,
                    child: settings.avatarUrl.isEmpty
                        ? Text(initial,
                            style: const TextStyle(
                                fontSize: 32, fontWeight: FontWeight.w600))
                        : null,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _editTextField(
                      context,
                      ref,
                      'Avatar URL',
                      settings.avatarUrl,
                      (v) => ref
                          .read(settingsProvider.notifier)
                          .update((s) => s.copyWith(avatarUrl: v)),
                    ),
                    child: Text(settings.avatarUrl.isEmpty
                        ? 'Add avatar'
                        : 'Change avatar'),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Display name'),
            subtitle: Text(settings.displayName.isEmpty
                ? 'Not set'
                : settings.displayName),
            onTap: () => _editTextField(context, ref, 'Display name',
                settings.displayName, (v) {
              ref.read(settingsProvider.notifier)
                  .update((s) => s.copyWith(displayName: v));
            }),
          ),
          ListTile(
            title: const Text('Bio'),
            subtitle: Text(
              settings.bio.isEmpty ? 'Tell ɳClaw a bit about you' : settings.bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _editTextField(
              context,
              ref,
              'Bio',
              settings.bio,
              (v) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(bio: v)),
              maxLines: 4,
            ),
          ),
          ListTile(
            title: const Text('Language'),
            subtitle: Text(settings.language),
          ),
          SwitchListTile(
            title: const Text('Launch at login'),
            value: settings.launchAtLogin,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(launchAtLogin: v)),
          ),
        ],
      ),
    );
  }
}

class _OllamaModel {
  final String name;
  final double sizeGb;
  final double ramRequiredGb;
  final String parameters;

  const _OllamaModel({
    required this.name,
    required this.sizeGb,
    required this.ramRequiredGb,
    required this.parameters,
  });

  factory _OllamaModel.fromJson(Map<String, dynamic> json) {
    return _OllamaModel(
      name: json['name'] as String,
      sizeGb: (json['size_gb'] as num).toDouble(),
      ramRequiredGb: (json['ram_required_gb'] as num).toDouble(),
      parameters: json['parameters'] as String,
    );
  }
}

const _fallbackModels = [
  _OllamaModel(name: 'llama3.2:3b', sizeGb: 2.0, ramRequiredGb: 3.5, parameters: '3B'),
  _OllamaModel(name: 'llama3.2:7b', sizeGb: 4.2, ramRequiredGb: 6.0, parameters: '7B'),
  _OllamaModel(name: 'gemma3:4b', sizeGb: 2.5, ramRequiredGb: 4.0, parameters: '4B'),
  _OllamaModel(name: 'mistral:7b', sizeGb: 4.1, ramRequiredGb: 6.0, parameters: '7B'),
  _OllamaModel(name: 'phi3:mini', sizeGb: 1.8, ramRequiredGb: 3.0, parameters: '3.8B'),
];

class _ModelSettings extends ConsumerStatefulWidget {
  const _ModelSettings();

  @override
  ConsumerState<_ModelSettings> createState() => _ModelSettingsState();
}

class _ModelSettingsState extends ConsumerState<_ModelSettings> {
  List<_OllamaModel>? _models;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchModels();
  }

  Future<void> _fetchModels() async {
    final serverUrl = ref.read(connectionProvider).activeServer?.url ?? '';
    if (serverUrl.isEmpty) {
      setState(() { _models = _fallbackModels; _loading = false; });
      return;
    }
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/ai/models'))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['models'] as List)
            .map((e) => _OllamaModel.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() { _models = list; _loading = false; });
      } else {
        setState(() { _models = _fallbackModels; _loading = false; });
      }
    } catch (_) {
      setState(() { _models = _fallbackModels; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final selected = settings.defaultModel;

    return Scaffold(
      appBar: AppBar(title: const Text('Model')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.lg, BrandSpacing.lg, BrandSpacing.lg, BrandSpacing.sm),
                  child: Text(
                    'Select model',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                // Auto option.
                _ModelTile(
                  name: 'auto',
                  displayName: 'Auto',
                  badge: 'Smart',
                  detail: 'Picks the best model for available RAM',
                  isSelected: selected == 'auto',
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(defaultModel: 'auto')),
                ),
                const Divider(height: 1),
                ...(_models ?? _fallbackModels).map((m) => _ModelTile(
                      name: m.name,
                      displayName: m.name,
                      badge: m.parameters,
                      detail: '${m.ramRequiredGb.toStringAsFixed(1)} GB RAM',
                      isSelected: selected == m.name,
                      onTap: () => ref
                          .read(settingsProvider.notifier)
                          .update((s) => s.copyWith(defaultModel: m.name)),
                    )),
                const Divider(height: BrandSpacing.lg),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      BrandSpacing.lg, BrandSpacing.sm, BrandSpacing.lg, BrandSpacing.sm),
                  child: Text(
                    'Generation',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ),
                ListTile(
                  title: const Text('Temperature'),
                  subtitle: Slider(
                    value: settings.temperature,
                    min: 0,
                    max: 2,
                    divisions: 20,
                    label: settings.temperature.toStringAsFixed(1),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .update((s) => s.copyWith(temperature: v)),
                  ),
                ),
                ListTile(
                  title: const Text('Max tokens'),
                  subtitle: Text('${settings.maxTokens}'),
                ),
              ],
            ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  final String name;
  final String displayName;
  final String badge;
  final String detail;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModelTile({
    required this.name,
    required this.displayName,
    required this.badge,
    required this.detail,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Row(
        children: [
          Expanded(
            child: Text(
              displayName,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? BrandColors.primary
                        : BrandColors.textHigh,
                  ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: BrandSpacing.sm, vertical: BrandSpacing.xs),
            decoration: BoxDecoration(
              color: BrandColors.primaryContainer,
              borderRadius: BorderRadius.circular(BrandRadii.sm),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BrandColors.textHigh),
            ),
          ),
        ],
      ),
      subtitle: Text(detail),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: BrandColors.primary)
          : const Icon(Icons.radio_button_unchecked,
              color: BrandColors.textDisabled),
    );
  }
}

class _AppearanceSettings extends ConsumerWidget {
  const _AppearanceSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(settings.theme),
            onTap: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: ['system', 'dark', 'light'].map((t) {
                      return RadioListTile<String>(
                        title: Text(t[0].toUpperCase() + t.substring(1)),
                        value: t,
                        groupValue: settings.theme,
                        onChanged: (v) {
                          ref.read(settingsProvider.notifier)
                              .update((s) => s.copyWith(theme: v));
                          Navigator.of(ctx).pop();
                        },
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
          ListTile(
            title: const Text('Font size'),
            subtitle: Slider(
              value: settings.fontSize,
              min: 10,
              max: 24,
              divisions: 14,
              label: settings.fontSize.toStringAsFixed(0),
              onChanged: (v) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(fontSize: v)),
            ),
          ),
          SwitchListTile(
            title: const Text('Compact mode'),
            value: settings.compactMode,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(compactMode: v)),
          ),
        ],
      ),
    );
  }
}

class _ApiKeysSettings extends ConsumerWidget {
  const _ApiKeysSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('API Keys')),
      body: settings.apiKeys.isEmpty
          ? const Center(child: Text('No API keys configured'))
          : ListView(
              children: settings.apiKeys.entries.map((entry) {
                return ListTile(
                  title: Text(entry.key),
                  subtitle: Text(
                    '${entry.value.substring(0, entry.value.length > 8 ? 8 : entry.value.length)}...',
                  ),
                  trailing: const Icon(Icons.delete_outline),
                );
              }).toList(),
            ),
    );
  }
}

class _PrivacySettings extends ConsumerWidget {
  const _PrivacySettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Biometric lock'),
            subtitle: const Text('Require Face ID / Touch ID on resume'),
            value: settings.biometricLock,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(biometricLock: v)),
          ),
          SwitchListTile(
            title: const Text('Analytics'),
            value: settings.analyticsEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(analyticsEnabled: v)),
          ),
          ListTile(
            title: const Text('Auto-lock timeout'),
            subtitle: Text('${settings.autoLockMinutes} minutes'),
          ),
        ],
      ),
    );
  }
}

class _NotificationSettings extends ConsumerWidget {
  const _NotificationSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Push notifications'),
            value: settings.pushEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(pushEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Sound'),
            value: settings.soundEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(soundEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Badge'),
            value: settings.badgeEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(badgeEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Daily digest'),
            value: settings.digestEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(digestEnabled: v)),
          ),
        ],
      ),
    );
  }
}

class _DataSettings extends ConsumerWidget {
  const _DataSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Data')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Offline mode'),
            subtitle: const Text('Cache data locally for offline access'),
            value: settings.offlineModeEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(offlineModeEnabled: v)),
          ),
          ListTile(
            title: const Text('Cache size limit'),
            subtitle: Text('${settings.cacheSizeMb} MB'),
          ),
          SwitchListTile(
            title: const Text('Auto sync'),
            value: settings.autoSync,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(autoSync: v)),
          ),
          ListTile(
            title: const Text('Sync interval'),
            subtitle: Text('Every ${settings.syncIntervalMinutes} minutes'),
          ),
          ListTile(
            title: const Text('Clear cache'),
            leading: const Icon(Icons.delete_sweep),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SharingSettings extends ConsumerWidget {
  const _SharingSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Sharing')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Share sheet extension'),
            subtitle: const Text('Show "Save to claw" in share sheet'),
            value: settings.shareSheetEnabled,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(shareSheetEnabled: v)),
          ),
          ListTile(
            title: const Text('Default share topic'),
            subtitle: Text(settings.defaultShareTopic.isEmpty
                ? 'Last used topic'
                : settings.defaultShareTopic),
          ),
        ],
      ),
    );
  }
}

class _BillingSettings extends ConsumerWidget {
  const _BillingSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Subscription'),
            subtitle: Text(settings.subscriptionTier ?? 'Free'),
          ),
          if (settings.subscriptionExpiry != null)
            ListTile(
              title: const Text('Expires'),
              subtitle: Text(
                  settings.subscriptionExpiry!.toLocal().toString().split(' ')[0]),
            ),
          ListTile(
            title: const Text('Manage subscription'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () {
              // Open billing portal.
            },
          ),
        ],
      ),
    );
  }
}

class _AdvancedSettings extends ConsumerWidget {
  const _AdvancedSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Advanced')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Debug mode'),
            value: settings.debugMode,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(debugMode: v)),
          ),
          ListTile(
            title: const Text('Custom endpoint'),
            subtitle: Text(settings.customEndpoint ?? 'Not set'),
            onTap: () => _editTextField(context, ref, 'Custom endpoint',
                settings.customEndpoint ?? '', (v) {
              ref.read(settingsProvider.notifier).update(
                  (s) => s.copyWith(customEndpoint: v.isEmpty ? null : v));
            }),
          ),
          SwitchListTile(
            title: const Text('Experimental features'),
            value: settings.experimentalFeatures,
            onChanged: (v) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(experimentalFeatures: v)),
          ),
        ],
      ),
    );
  }
}

class _BetaProgramSettings extends ConsumerStatefulWidget {
  const _BetaProgramSettings();

  @override
  ConsumerState<_BetaProgramSettings> createState() =>
      _BetaProgramSettingsState();
}

class _BetaProgramSettingsState extends ConsumerState<_BetaProgramSettings> {
  bool _opted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await BetaChannelService.isBetaOptedIn();
    if (mounted) setState(() { _opted = v; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Beta Program')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  title: const Text('Join beta program'),
                  subtitle: const Text(
                    'Get early access to new features. Beta builds may be less stable.',
                  ),
                  value: _opted,
                  onChanged: (v) async {
                    await BetaChannelService.setBetaOptIn(v);
                    setState(() => _opted = v);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v
                              ? 'Joined beta program. Updates will switch on next check.'
                              : 'Left beta program. Returning to stable channel.'),
                        ),
                      );
                    }
                  },
                ),
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'On iOS, beta builds are delivered via TestFlight. '
                    'On Android, via Play Internal Test. '
                    'On desktop, the auto-update feed switches to the beta channel.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ],
            ),
    );
  }
}

class _AboutSettings extends StatelessWidget {
  const _AboutSettings();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('nClaw'),
            subtitle: Text('v1.1.0'),
          ),
          ListTile(
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://claw.nself.org/privacy')),
          ),
          ListTile(
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://claw.nself.org/terms')),
          ),
          ListTile(
            title: const Text('Support'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => launchUrl(Uri.parse('https://claw.nself.org/support')),
          ),
          const ListTile(
            title: Text('License'),
            subtitle: Text('MIT'),
          ),
        ],
      ),
    );
  }
}

// -- Pool Management ---------------------------------------------------------

class _GeminiAccount {
  final String id;
  final String email;
  final String status;
  final int dailyRequestsUsed;
  final int dailyLimit;

  const _GeminiAccount({
    required this.id,
    required this.email,
    required this.status,
    required this.dailyRequestsUsed,
    required this.dailyLimit,
  });

  bool get isActive => status == 'active';

  factory _GeminiAccount.fromJson(Map<String, dynamic> json) {
    return _GeminiAccount(
      id: json['id'] as String,
      email: json['email'] as String,
      status: json['status'] as String,
      dailyRequestsUsed: (json['daily_requests_used'] as num).toInt(),
      dailyLimit: (json['daily_limit'] as num).toInt(),
    );
  }
}

class _PoolManagementScreen extends ConsumerStatefulWidget {
  const _PoolManagementScreen();

  @override
  ConsumerState<_PoolManagementScreen> createState() =>
      _PoolManagementScreenState();
}

class _PoolManagementScreenState extends ConsumerState<_PoolManagementScreen> {
  List<_GeminiAccount>? _accounts;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAccounts();
  }

  Future<void> _fetchAccounts() async {
    setState(() { _loading = true; _error = null; });
    final serverUrl = ref.read(connectionProvider).activeServer?.url ?? '';
    if (serverUrl.isEmpty) {
      setState(() { _loading = false; _accounts = []; });
      return;
    }
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/ai/gemini/accounts'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final list = (data['accounts'] as List)
            .map((e) => _GeminiAccount.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() { _accounts = list; _loading = false; });
      } else {
        setState(() { _error = 'Server returned ${response.statusCode}'; _loading = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _deleteAccount(String accountId) async {
    final serverUrl = ref.read(connectionProvider).activeServer?.url ?? '';
    if (serverUrl.isEmpty) return;
    try {
      await http
          .delete(Uri.parse('$serverUrl/ai/gemini/accounts/$accountId'))
          .timeout(const Duration(seconds: 10));
      await _fetchAccounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove account: $e')),
        );
      }
    }
  }

  Future<void> _addAccount() async {
    final serverUrl = ref.read(connectionProvider).activeServer?.url ?? '';
    if (serverUrl.isEmpty) return;
    try {
      final response = await http
          .get(Uri.parse('$serverUrl/ai/gemini/auth-url'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not start auth: ${response.statusCode}')),
          );
        }
        return;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final authUrl = data['auth_url'] as String;
      final redirectUri = data['redirect_uri'] as String;

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OAuthScreen(
            authUrl: authUrl,
            redirectUri: redirectUri,
            service: 'google',
          ),
        ),
      );
      await _fetchAccounts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start account link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = EmptyState.error(
        title: 'Could not load accounts',
        message: _error,
        onRetry: _fetchAccounts,
      );
    } else if (_accounts == null || _accounts!.isEmpty) {
      body = EmptyState.firstTime(
        icon: Icons.account_circle_outlined,
        title: 'No accounts linked',
        message: 'Add a Google account to use free Gemini quota.',
        primaryAction: EmptyStateAction(
          label: 'Add Gemini account',
          icon: Icons.add,
          onPressed: _addAccount,
        ),
      );
    } else {
      body = ListView.builder(
        itemCount: _accounts!.length,
        itemBuilder: (context, index) {
          final account = _accounts![index];
          final initial = account.email.isNotEmpty
              ? account.email[0].toUpperCase()
              : '?';
          final subtitleText = account.isActive
              ? '${account.dailyRequestsUsed}/${account.dailyLimit} requests today'
              : 'Revoked';

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: BrandColors.primaryContainer,
              child: Text(
                initial,
                style: const TextStyle(
                    color: BrandColors.textHigh, fontWeight: FontWeight.w600),
              ),
            ),
            title: Text(account.email),
            subtitle: Text(
              subtitleText,
              style: TextStyle(
                color: account.isActive ? BrandColors.textLow : BrandColors.error,
              ),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove account',
              onPressed: () => _deleteAccount(account.id),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Account pool')),
      body: body,
      floatingActionButton: (!_loading && _error == null && (_accounts?.isNotEmpty ?? false))
          ? FloatingActionButton.extended(
              onPressed: _addAccount,
              icon: const Icon(Icons.add),
              label: const Text('Add Gemini account'),
            )
          : null,
    );
  }
}

// -- Helpers -----------------------------------------------------------------

void _editTextField(
  BuildContext context,
  WidgetRef ref,
  String label,
  String currentValue,
  void Function(String) onSave, {
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: currentValue);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: label,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            onSave(controller.text.trim());
            Navigator.of(ctx).pop();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
