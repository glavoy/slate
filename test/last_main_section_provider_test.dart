import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slate/providers/settings_providers.dart';

void main() {
  Future<String> loadStoredSection(String? section) async {
    SharedPreferences.setMockInitialValues(
      section == null ? <String, Object>{} : {'last_main_section': section},
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(lastMainSectionNotifierProvider.notifier).init();
    return container.read(lastMainSectionNotifierProvider);
  }

  test('restores a valid last main section', () async {
    expect(await loadStoredSection('notes'), 'notes');
  });

  test('defaults to tasks when no section was stored', () async {
    expect(await loadStoredSection(null), defaultMainSectionName);
  });

  test('defaults to tasks when the stored section is invalid', () async {
    expect(await loadStoredSection('archived'), defaultMainSectionName);
  });

  test('persists a valid selection and rejects invalid selections', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(lastMainSectionNotifierProvider.notifier);

    await notifier.set('tracker');
    expect(container.read(lastMainSectionNotifierProvider), 'tracker');

    await notifier.set('unsupported');
    expect(
      container.read(lastMainSectionNotifierProvider),
      defaultMainSectionName,
    );
  });
}
