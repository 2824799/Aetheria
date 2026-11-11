import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:aetheria/core/providers/ui_theme_provider.dart';
import 'package:aetheria/core/widgets/aether_pressable.dart';
import 'package:aetheria/core/widgets/aether_text_field.dart';
import 'package:aetheria/core/widgets/aether_toast.dart';

/// A line of text that turns into a text field when clicked.
///
/// Enter or losing focus saves through [onSave]; Escape cancels. When
/// [onSave] throws, the reason is shown and the old value is restored.
class EditableMetadataText extends StatefulWidget {
  const EditableMetadataText({
    super.key,
    required this.value,
    required this.emptyText,
    required this.style,
    required this.onSave,
    this.tooltip,
  });

  final String value;

  /// Shown, dimmed, while [value] is empty.
  final String emptyText;
  final TextStyle style;
  final String? tooltip;
  final Future<void> Function(String value) onSave;

  @override
  State<EditableMetadataText> createState() => _EditableMetadataTextState();
}

class _EditableMetadataTextState extends State<EditableMetadataText> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;
  bool _isEditing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant EditableMetadataText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isEditing && oldWidget.value != widget.value) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (_isEditing && !_focusNode.hasFocus && !_isSaving) {
      _commit();
    }
  }

  void _startEditing() {
    if (_isEditing) return;
    setState(() {
      _isEditing = true;
      _controller.text = widget.value;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _stopEditing() {
    setState(() => _isEditing = false);
    _focusNode.unfocus();
  }

  void _cancel() {
    _controller.text = widget.value;
    _stopEditing();
  }

  Future<void> _commit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_controller.text.trim());
    } catch (e) {
      if (mounted) {
        showAetherToast(
          context,
          message: '保存失败: $e',
          kind: AetherToastKind.error,
        );
        _controller.text = widget.value;
      }
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    _stopEditing();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final value = widget.value.trim();
    final highlighted = _isHovered || _isEditing;

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AetherPressable(
        pressScale: 1,
        onTap: _startEditing,
        tooltip: _isEditing ? null : widget.tooltip,
        child: AnimatedContainer(
          duration: AetherMotion.duration(context, AetherMotion.press),
          padding: const EdgeInsets.symmetric(
            horizontal: AetherSpace.sm,
            vertical: AetherSpace.xxs,
          ),
          decoration: BoxDecoration(
            color: highlighted ? cfg.bgHover : Colors.transparent,
            borderRadius: BorderRadius.circular(AetherRadius.sm),
            border: Border.all(
              color: _isEditing ? cfg.borderFocus : Colors.transparent,
            ),
          ),
          child: _isEditing
              ? Focus(
                  onKeyEvent: _handleKey,
                  child: AetherTextField.plain(
                    controller: _controller,
                    focusNode: _focusNode,
                    textAlign: TextAlign.left,
                    enabled: !_isSaving,
                    onSubmitted: (_) => _commit(),
                    style: widget.style,
                    contentPadding: EdgeInsets.zero,
                  ),
                )
              : Text(
                  value.isEmpty ? widget.emptyText : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: value.isEmpty
                      ? widget.style.copyWith(color: cfg.textTertiary)
                      : widget.style,
                ),
        ),
      ),
    );
  }
}
