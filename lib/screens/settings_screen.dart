import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_providers.dart';
import '../providers/supabase_provider.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    final dateStyle = ref.watch(dateFormatNotifierProvider);
    final timeStyle = ref.watch(timeFormatNotifierProvider);
    final user = ref.watch(currentUserProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(theme: theme, label: 'APPEARANCE'),
          SwitchListTile(
            secondary: Icon(themeMode == ThemeMode.dark
                ? Icons.dark_mode_outlined
                : Icons.light_mode_outlined),
            title: Text(
                themeMode == ThemeMode.dark ? 'Dark mode' : 'Light mode'),
            value: themeMode == ThemeMode.dark,
            onChanged: (_) =>
                ref.read(themeNotifierProvider.notifier).toggle(),
          ),

          const Divider(height: 24),
          _SectionHeader(theme: theme, label: 'FORMATS'),

          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('Date format'),
            subtitle: Text(dateStyle.example),
            trailing: DropdownButton<DateFormatStyle>(
              value: dateStyle,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(dateFormatNotifierProvider.notifier).set(v);
                }
              },
              items: [
                for (final s in DateFormatStyle.values)
                  DropdownMenuItem(value: s, child: Text(s.example)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.access_time_outlined),
            title: const Text('Time format'),
            subtitle: Text(timeStyle.example),
            trailing: DropdownButton<TimeFormatStyle>(
              value: timeStyle,
              underline: const SizedBox.shrink(),
              onChanged: (v) {
                if (v != null) {
                  ref.read(timeFormatNotifierProvider.notifier).set(v);
                }
              },
              items: [
                for (final s in TimeFormatStyle.values)
                  DropdownMenuItem(value: s, child: Text(s.example)),
              ],
            ),
          ),

          const Divider(height: 24),
          _SectionHeader(theme: theme, label: 'ACCOUNT'),

          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.email ?? 'Signed out'),
            subtitle: const Text('Signed in'),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: colorScheme.error),
            title: Text(
              'Sign out',
              style: TextStyle(color: colorScheme.error),
            ),
            onTap: () =>
                ref.read(supabaseClientProvider).auth.signOut(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final ThemeData theme;
  final String label;
  const _SectionHeader({required this.theme, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
