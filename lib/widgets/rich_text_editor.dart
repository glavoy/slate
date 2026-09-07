import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Creates a Quill document from the app's stored rich-text representation.
/// Non-Delta values are shown as ordinary text without any transformation.
Document documentFromStoredContent(String content) {
  if (content.trim().isEmpty) return Document();
  try {
    final decoded = jsonDecode(content);
    if (decoded is List) return Document.fromJson(decoded);
  } catch (_) {
    // The content is plain text, not a rich-text Delta.
  }
  return Document()..insert(0, content);
}

String serializeDocument(QuillController controller) =>
    jsonEncode(controller.document.toDelta().toJson());

void focusQuillEditor(QuillController controller, FocusNode editorFocusNode) {
  if (!editorFocusNode.canRequestFocus) return;

  final selection = controller.selection;
  final maxOffset = controller.document.length - 1;
  final safeMaxOffset = maxOffset < 0 ? 0 : maxOffset;
  final safeSelection = selection.isValid
      ? selection.copyWith(
          baseOffset: selection.baseOffset.clamp(0, safeMaxOffset),
          extentOffset: selection.extentOffset.clamp(0, safeMaxOffset),
        )
      : const TextSelection.collapsed(offset: 0);
  if (safeSelection != selection) {
    controller.updateSelection(safeSelection, ChangeSource.local);
  }
  editorFocusNode.requestFocus();
}

bool deleteExpandedQuillSelection(QuillController controller) {
  final selection = controller.selection;
  if (!selection.isValid || selection.isCollapsed) return false;

  controller.replaceText(
    selection.start,
    selection.end - selection.start,
    '',
    TextSelection.collapsed(offset: selection.start),
  );
  return true;
}

QuillController createSelectionSafeQuillController({
  Document? document,
  TextSelection selection = const TextSelection.collapsed(offset: 0),
}) {
  late final QuillController controller;
  controller = QuillController(
    document: document ?? Document(),
    selection: selection,
    onReplaceText: (index, length, replacement) {
      final currentSelection = controller.selection;
      final isSelectionDelete =
          replacement is String &&
          replacement.isEmpty &&
          length > 0 &&
          currentSelection.isValid &&
          !currentSelection.isCollapsed &&
          index == currentSelection.start &&
          length == currentSelection.end - currentSelection.start;
      if (!isSelectionDelete) return true;

      controller.document.delete(index, length);
      controller.updateSelection(
        TextSelection.collapsed(offset: index),
        ChangeSource.local,
      );
      return false;
    },
  );
  return controller;
}

KeyEventResult? handleSelectionSafeDeleteKey(
  QuillController controller,
  KeyEvent event,
) {
  if (event is! KeyDownEvent && event is! KeyRepeatEvent) return null;
  if (event.logicalKey != LogicalKeyboardKey.backspace &&
      event.logicalKey != LogicalKeyboardKey.delete) {
    return null;
  }
  return deleteExpandedQuillSelection(controller)
      ? KeyEventResult.handled
      : null;
}

class SelectionSafeDeleteAction<T extends DirectionalTextEditingIntent>
    extends Action<T> {
  SelectionSafeDeleteAction(this.controller);

  final QuillController controller;

  @override
  Object? invoke(T intent) {
    if (deleteExpandedQuillSelection(controller)) return null;
    return callingAction?.invoke(intent);
  }

  @override
  bool get isActionEnabled => true;
}

class RichTextFormatToolbar extends StatelessWidget {
  const RichTextFormatToolbar({
    super.key,
    required this.controller,
    required this.editorFocusNode,
  });

  final QuillController controller;
  final FocusNode editorFocusNode;

  void _withFocus(VoidCallback action) {
    action();
    editorFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (editorFocusNode.canRequestFocus) editorFocusNode.requestFocus();
    });
  }

  void _toggleInline(Attribute attr) {
    final style = controller.getSelectionStyle();
    final isActive = style.attributes.containsKey(attr.key);
    controller.formatSelection(isActive ? Attribute.clone(attr, null) : attr);
  }

  void _toggleBlock(Attribute attr) {
    final current = controller.getSelectionStyle().attributes[attr.key];
    controller.formatSelection(
      current != null && current.value == attr.value
          ? Attribute.clone(attr, null)
          : attr,
    );
  }

  void _toggleCheckbox() {
    final current = controller
        .getSelectionStyle()
        .attributes[Attribute.list.key];
    final isCheckbox =
        current?.value == Attribute.unchecked.value ||
        current?.value == Attribute.checked.value;
    controller.formatSelection(
      isCheckbox
          ? Attribute.clone(Attribute.unchecked, null)
          : Attribute.unchecked,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
    );
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          border: Border(top: border),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final attrs = controller.getSelectionStyle().attributes;
            final isLarge =
                attrs[Attribute.header.key]?.value == 1 ||
                attrs[Attribute.header.key]?.value == 2;
            final listValue = attrs[Attribute.list.key]?.value;
            final isCheckbox =
                listValue == Attribute.unchecked.value ||
                listValue == Attribute.checked.value;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToggleTextButton(
                    label: 'B',
                    tooltip: 'Bold',
                    active: attrs.containsKey(Attribute.bold.key),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.bold)),
                  ),
                  _ToggleTextButton(
                    label: 'I',
                    tooltip: 'Italic',
                    active: attrs.containsKey(Attribute.italic.key),
                    textStyle: const TextStyle(fontStyle: FontStyle.italic),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.italic)),
                  ),
                  _ToggleTextButton(
                    label: 'U',
                    tooltip: 'Underline',
                    active: attrs.containsKey(Attribute.underline.key),
                    textStyle: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                    onPressed: () =>
                        _withFocus(() => _toggleInline(Attribute.underline)),
                  ),
                  const SizedBox(width: 8),
                  _ToggleTextButton(
                    label: 'A−',
                    tooltip: 'Normal text',
                    active: !isLarge,
                    onPressed: () => _withFocus(
                      () => controller.formatSelection(Attribute.header),
                    ),
                  ),
                  _ToggleTextButton(
                    label: 'A+',
                    tooltip: 'Large text',
                    active: isLarge,
                    onPressed: () => _withFocus(
                      () => controller.formatSelection(Attribute.h2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _ToggleIconButton(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    active: listValue == Attribute.ul.value,
                    onPressed: () =>
                        _withFocus(() => _toggleBlock(Attribute.ul)),
                  ),
                  _ToggleIconButton(
                    icon: Icons.format_list_numbered,
                    tooltip: 'Numbered list',
                    active: listValue == Attribute.ol.value,
                    onPressed: () =>
                        _withFocus(() => _toggleBlock(Attribute.ol)),
                  ),
                  _ToggleIconButton(
                    icon: Icons.check_box_outlined,
                    tooltip: 'Checkbox',
                    active: isCheckbox,
                    onPressed: () => _withFocus(_toggleCheckbox),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ToggleTextButton extends StatelessWidget {
  const _ToggleTextButton({
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.textStyle,
  });
  final String label;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  final TextStyle? textStyle;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: TextButton(
        style: TextButton.styleFrom(
          minimumSize: const Size(40, 36),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          backgroundColor: active ? cs.secondaryContainer : null,
          foregroundColor: active ? cs.onSecondaryContainer : cs.onSurface,
          visualDensity: VisualDensity.compact,
        ),
        onPressed: onPressed,
        child: Text(label, style: textStyle),
      ),
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
  });
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(icon),
      iconSize: 20,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: active ? cs.secondaryContainer : null,
        foregroundColor: active ? cs.onSecondaryContainer : cs.onSurface,
      ),
      onPressed: onPressed,
    );
  }
}
