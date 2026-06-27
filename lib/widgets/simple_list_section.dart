import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/simple_list_providers.dart';

const _bullet = '- ';
const _legacyBullet = '• ';
const _debounceDuration = Duration(milliseconds: 1200);
const _idleBeforeRemoteSync = Duration(seconds: 3);
final _bulletFormatter = _BulletFormatter();

class SimpleListSection extends ConsumerStatefulWidget {
  const SimpleListSection({super.key});

  @override
  ConsumerState<SimpleListSection> createState() => _SimpleListSectionState();
}

class _SimpleListSectionState extends ConsumerState<SimpleListSection> {
  final _controller = _QuickListController();
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

  void _initialize(String content) {
    final initial = _normalizeBullets(content.isEmpty ? _bullet : content);
    _controller.text = initial;
    _lastSavedContent = initial;
    _initialized = true;
  }

  void _applyRemote(String remoteContent) {
    remoteContent = _normalizeBullets(remoteContent);
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
          _initialize(list.content);
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
        child: Text('Quick list error: $e'),
      ),
      data: (list) {
        if (!_initialized) {
          _initialize(list.content);
        }

        return Padding(
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
                  style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '- Add quick items here',
                  ),
                  onChanged: _onChanged,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

String _normalizeBullets(String text) {
  if (text == _legacyBullet.trim()) return _bullet;
  return text
      .split('\n')
      .map((line) {
        if (line == _legacyBullet.trim()) return _bullet;
        if (line.startsWith(_legacyBullet)) {
          return _bullet + line.substring(_legacyBullet.length);
        }
        return line;
      })
      .join('\n');
}

class _QuickListController extends TextEditingController {
  static const double _iconSize = 18.0;
  static const double _iconGap = 6.0;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base =
        style ?? Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    final colorScheme = Theme.of(context).colorScheme;
    final lines = text.split('\n');
    final children = <InlineSpan>[];

    for (var i = 0; i < lines.length; i++) {
      if (i > 0) children.add(const TextSpan(text: '\n'));

      final line = lines[i];
      if (!line.startsWith(_bullet)) {
        children.add(TextSpan(text: line));
        continue;
      }

      children.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          baseline: TextBaseline.alphabetic,
          child: SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: Center(
              child: Icon(
                Icons.circle,
                size: 7.0,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      );
      children.add(
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SizedBox(width: _iconGap, height: _iconSize),
        ),
      );

      if (line.length > _bullet.length) {
        children.add(TextSpan(text: line.substring(_bullet.length)));
      }
    }

    return TextSpan(style: base, children: children);
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

    final normalized = _normalizeBullets(newValue.text);
    if (normalized != newValue.text) {
      final delta = normalized.length - newValue.text.length;
      return TextEditingValue(
        text: normalized,
        selection: TextSelection.collapsed(
          offset: (newValue.selection.baseOffset + delta).clamp(
            0,
            normalized.length,
          ),
        ),
      );
    }

    // User backspaced the trailing space from the first bullet (-  → -); fix
    // in-place instead of prepending a second bullet symbol.
    if (newValue.text.startsWith('-') && !newValue.text.startsWith(_bullet)) {
      final fixed = _bullet + newValue.text.substring(1);
      final offset = (newValue.selection.baseOffset + 1).clamp(0, fixed.length);
      return TextEditingValue(
        text: fixed,
        selection: TextSelection.collapsed(offset: offset),
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
          final updated = newValue.text.substring(0, cursor) + _bullet + after;
          return TextEditingValue(
            text: updated,
            selection: TextSelection.collapsed(offset: cursor + _bullet.length),
          );
        }
      }
    }

    return newValue;
  }
}
