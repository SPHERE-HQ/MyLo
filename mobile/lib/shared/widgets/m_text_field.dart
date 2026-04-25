import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme.dart';

enum MTextFieldType { normal, password, search, phone }

class MTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int? maxLines;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool enabled;
  final MTextFieldType _type;
  final VoidCallback? onClear;
  final String? countryCode;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final VoidCallback? onEditingComplete;

  const MTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.onClear,
    this.countryCode,
    this.inputFormatters,
    this.textInputAction,
    this.onEditingComplete,
  }) : _type = MTextFieldType.normal;

  const MTextField.search({
    super.key,
    this.controller,
    this.hint = 'Cari...',
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.onClear,
    this.textInputAction = TextInputAction.search,
    this.onEditingComplete,
  })  : label = null,
        prefixIcon = Icons.search,
        suffix = null,
        obscureText = false,
        keyboardType = TextInputType.text,
        validator = null,
        maxLines = 1,
        countryCode = null,
        inputFormatters = null,
        _type = MTextFieldType.search;

  const MTextField.phone({
    super.key,
    this.controller,
    this.label = 'Nomor HP',
    this.hint = '08xx-xxxx-xxxx',
    this.onChanged,
    this.autofocus = false,
    this.enabled = true,
    this.validator,
    this.countryCode = '+62',
    this.textInputAction,
    this.onEditingComplete,
  })  : prefixIcon = null,
        suffix = null,
        obscureText = false,
        keyboardType = TextInputType.phone,
        maxLines = 1,
        onClear = null,
        inputFormatters = null,
        _type = MTextFieldType.phone;

  @override
  State<MTextField> createState() => _MTextFieldState();
}

class _MTextFieldState extends State<MTextField> {
  bool _obscure = true;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    if (widget.obscureText) _obscure = true;
    widget.controller?.addListener(_onTextChange);
  }

  void _onTextChange() {
    final has = (widget.controller?.text.isNotEmpty) ?? false;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onTextChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget? buildSuffix() {
      if (widget.obscureText) {
        return IconButton(
          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        );
      }
      if (widget._type == MTextFieldType.search && _hasText) {
        return IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: () {
            widget.controller?.clear();
            widget.onClear?.call();
            widget.onChanged?.call('');
          },
        );
      }
      return widget.suffix;
    }

    Widget? buildPrefix() {
      if (widget._type == MTextFieldType.phone && widget.countryCode != null) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(widget.countryCode!,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(width: 4),
            Container(
                width: 1, height: 20,
                color: MyloColors.textTertiary),
          ]),
        );
      }
      if (widget.prefixIcon != null) {
        return Icon(widget.prefixIcon, size: 20);
      }
      return null;
    }

    final textField = TextFormField(
      controller: widget.controller,
      obscureText: widget.obscureText ? _obscure : false,
      keyboardType: widget.keyboardType,
      validator: widget.validator,
      maxLines: widget.obscureText ? 1 : widget.maxLines,
      onChanged: widget.onChanged,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      inputFormatters: widget.inputFormatters,
      textInputAction: widget.textInputAction,
      onEditingComplete: widget.onEditingComplete,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: buildPrefix(),
        suffixIcon: buildSuffix(),
        filled: true,
        fillColor: isDark ? MyloColors.surfaceSecondaryDark : MyloColors.surfaceSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              widget._type == MTextFieldType.search
                  ? MyloRadius.full
                  : MyloRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              widget._type == MTextFieldType.search
                  ? MyloRadius.full
                  : MyloRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(
              widget._type == MTextFieldType.search
                  ? MyloRadius.full
                  : MyloRadius.md),
          borderSide:
              const BorderSide(color: MyloColors.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 14),
      ),
    );

    if (widget.label == null) return textField;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? MyloColors.textSecondaryDark
                  : MyloColors.textSecondary,
            )),
        const SizedBox(height: MyloSpacing.xs),
        textField,
      ],
    );
  }
}
