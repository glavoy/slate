import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/simple_list_providers.dart';

const _bullet = '• ';
const _debounceDuration = Duration(milliseconds: 1200);
const _idleBeforeRemoteSync = Duration(seconds: 3);
final _bulletFormatter = _BulletFormatter();

class SimpleListSection extends ConsumerStatefulWidget {
  const SimpleListSection({super.key});

  @override
  ConsumerState<SimpleListSection> createState() => _SimpleListSectionState();
}

class _SimpleListSectionState extends ConsumerState<SimpleListSection> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _lastSavedContent = '';
  DateTime _lastLocalEdit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _initialized = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _lastLocalEdit = DateTime.now();
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      _lastSavedContent = value;
      ref.read(simpleListNotifierProvider.notifier).save(value);
    });
  }

  void _applyRemote(String remoteContent) {
    if (remoteContent == _controller.text) return;
    if (remoteContent == _lastSavedContent) return;
    if (DateTime.now().difference(_lastLocalEdit) < _idleBeforeRemoteSync) {
      return;
    }
    _controller.value = TextEditingValue(
      text: remoteContent,
      selection: TextSelection.collapsed(offset: remoteContent.length),
    );
    _lastSavedContent = remoteContent;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asyncList = ref.watch(simpleListNotifierProvider);

    ref.listen(simpleListNotifierProvider, (prev, next) {
      next.whenData((list) {
        if (!_initialized) {
          final initial = list.content.isEmpty ? _bullet : list.content;
          _controller.text = initial;
          _lastSavedContent = initial;
          _initialized = true;
          return;
        }
        _applyRemote(list.content);
      });
    });

    return asyncList.when(
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Text('Simple list error: $e'),
      ),
      data: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 240),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: TextField(
                controller: _controller,
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                inputFormatters: [_bulletFormatter],
                style: theme.textTheme.bodyLarge,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: '• Add quick items here',
                ),
                onChanged: _onChanged,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BulletFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return const TextEditingValue(
        text: _bullet,
        selection: TextSelection.collapsed(offset: _bullet.length),
      );
    }

    if (!newValue.text.startsWith(_bullet)) {
      final fixed = _bullet + newValue.text;
      final delta = _bullet.length;
      return TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(
          offset: newValue.selection.baseOffset + delta,
        ),
      );
    }

    final inserted = newValue.text.length - oldValue.text.length;
    if (inserted == 1 && newValue.selection.isCollapsed) {
      final cursor = newValue.selection.baseOffset;
      if (cursor > 0 && newValue.text[cursor - 1] == '\n') {
        final after = newValue.text.substring(cursor);
        if (!after.startsWith(_bullet)) {
          final updated =
              newValue.text.substring(0, cursor) + _bullet + after;
          return TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(
              offset: cursor + _bullet.length,
            ),
          );
        }
      }
    }

    return newValue;
  }
}
