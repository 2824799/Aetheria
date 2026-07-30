import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aetheria/core/theme/aetheria_theme.dart';
import 'package:aetheria/core/theme/tokens/radius.dart';
import 'package:aetheria/core/theme/tokens/space.dart';
import 'package:aetheria/core/theme/tokens/typography.dart';

enum AetherTextFieldVariant { outlined, plain }

class AetherTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? hintText;
  final String? label;
  final bool obscureText;
  final bool enabled;
  final bool autofocus;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Widget? prefix;
  final Widget? suffix;
  final double? height;
  final EdgeInsetsGeometry? contentPadding;
  final AetherTextFieldVariant variant;
  final TextAlign textAlign;
  final TextStyle? style;

  const AetherTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.label,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.prefix,
    this.suffix,
    this.height,
    this.contentPadding,
    this.variant = AetherTextFieldVariant.outlined,
    this.textAlign = TextAlign.start,
    this.style,
  });

  /// Borderless inline editor for titles / artists in detail headers.
  const AetherTextField.plain({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText,
    this.label,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.prefix,
    this.suffix,
    this.height,
    this.contentPadding,
    this.textAlign = TextAlign.center,
    this.style,
  }) : variant = AetherTextFieldVariant.plain;

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final isMultiline = maxLines > 1 || (minLines != null && minLines! > 1);
    final radius = BorderRadius.circular(AetherRadius.md);
    final isPlain = variant == AetherTextFieldVariant.plain;

    final InputBorder none = InputBorder.none;
    final outlined = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cfg.borderSubtle),
    );
    final outlinedFocus = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cfg.borderFocus, width: 1.5),
    );
    final outlinedDisabled = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: cfg.borderSubtle.withValues(alpha: 0.5)),
    );

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: obscureText,
      enabled: enabled,
      autofocus: autofocus,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      textAlign: textAlign,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      cursorColor: cfg.accent,
      style: style ?? AetherType.bodyStyle(cfg.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: (style ?? AetherType.bodyStyle(cfg.textTertiary)).copyWith(
          color: cfg.textTertiary,
        ),
        prefixIcon: prefix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(left: 10, right: 6),
                child: prefix,
              ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: suffix == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: suffix,
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        contentPadding: contentPadding ??
            (isPlain
                ? const EdgeInsets.symmetric(vertical: AetherSpace.xxs)
                : EdgeInsets.symmetric(
                    horizontal: AetherSpace.lg,
                    vertical: isMultiline ? AetherSpace.lg : 10,
                  )),
        filled: true,
        fillColor: isPlain ? Colors.transparent : cfg.bgHover,
        border: isPlain ? none : outlined,
        enabledBorder: isPlain ? none : outlined,
        disabledBorder: isPlain ? none : outlinedDisabled,
        focusedBorder: isPlain ? none : outlinedFocus,
      ),
    );

    final boxed = isPlain
        ? field
        : SizedBox(
            height: isMultiline ? null : (height ?? AetherSpace.controlHeight),
            child: field,
          );

    if (label == null) return boxed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label!, style: AetherType.labelStyle(cfg.textSecondary)),
        const SizedBox(height: AetherSpace.xs),
        boxed,
      ],
    );
  }
}

class AetherSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const AetherSearchField({
    super.key,
    this.controller,
    this.focusNode,
    this.hintText = '搜索…',
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cfg = context.tokens;
    final textController = controller;

    Widget? suffix;
    if (textController != null) {
      suffix = ValueListenableBuilder<TextEditingValue>(
        valueListenable: textController,
        builder: (context, value, _) {
          if (value.text.isEmpty) return const SizedBox.shrink();
          return GestureDetector(
            onTap: () {
              textController.clear();
              onChanged?.call('');
              onClear?.call();
            },
            child: Icon(Icons.close, size: 14, color: cfg.textTertiary),
          );
        },
      );
    }

    return AetherTextField(
      controller: textController,
      focusNode: focusNode,
      hintText: hintText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      prefix: Icon(Icons.search, size: 16, color: cfg.textTertiary),
      suffix: suffix,
    );
  }
}
