import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../../../core/theme.dart';

/// A segmented OTP input: [length] single-digit boxes styled like the app's
/// `ZadTextField` (surface fill, [ZadRadii.button] radius). Typing a digit
/// auto-advances to the next box; backspace on an empty box steps back and
/// clears the previous digit; entering or pasting the full code into any box
/// distributes the digits across every box. The combined code is mirrored into
/// [controller] on every change, and [onCompleted] fires once all [length]
/// boxes hold a digit.
///
/// A [FormField] so an enclosing [Form]'s validate()/error display keeps
/// working; the boxes are plain [TextField]s (validation lives on the
/// FormField), so a test can drive the whole field via
/// `find.byType(TextField).first`.
///
/// Wrapped in a forced-LTR [Directionality] so an Arabic UI keeps the digits in
/// left-to-right order (the app's Western-digit convention for numbers).
class ZadOtpField extends StatefulWidget {
  const ZadOtpField({
    required this.controller,
    this.onCompleted,
    this.length = kOtpLength,
    this.validator,
    this.semanticsLabel,
    super.key,
  });

  final TextEditingController controller;
  final VoidCallback? onCompleted;
  final int length;
  final String? Function(String?)? validator;
  final String? semanticsLabel;

  @override
  State<ZadOtpField> createState() => _ZadOtpFieldState();
}

class _ZadOtpFieldState extends State<ZadOtpField> {
  late final List<TextEditingController> _boxes;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _boxes = List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
    // Seed the boxes from any value already on the shared controller.
    final seed = widget.controller.text.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < widget.length && i < seed.length; i++) {
      _boxes[i].text = seed[i];
    }
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _code => _boxes.map((c) => c.text).join();

  void _sync(FormFieldState<String> field) {
    final code = _code;
    widget.controller.text = code;
    field.didChange(code);
    if (code.length == widget.length) {
      widget.onCompleted?.call();
    }
  }

  /// Spread [digits] across the boxes from box 0 (paste / full-code entry),
  /// then focus the first empty box, or the last box when full.
  void _distribute(String digits) {
    for (var i = 0; i < widget.length; i++) {
      _boxes[i].text = i < digits.length ? digits[i] : '';
    }
    final target = digits.length >= widget.length ? widget.length - 1 : digits.length;
    _nodes[target].requestFocus();
  }

  void _onChanged(int i, String raw, FormFieldState<String> field) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= widget.length) {
      // Paste / full-code entry into a box: distribute across all boxes.
      _distribute(digits.substring(0, widget.length));
    } else if (digits.isEmpty) {
      _boxes[i].text = '';
    } else {
      // Keep just the latest digit in this box, then advance.
      final d = digits[digits.length - 1];
      if (_boxes[i].text != d) {
        _boxes[i].value = TextEditingValue(
          text: d,
          selection: const TextSelection.collapsed(offset: 1),
        );
      }
      if (i < widget.length - 1) {
        _nodes[i + 1].requestFocus();
      }
    }
    _sync(field);
  }

  KeyEventResult _onKey(int i, KeyEvent event, FormFieldState<String> field) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _boxes[i].text.isEmpty &&
        i > 0) {
      _boxes[i - 1].text = '';
      _nodes[i - 1].requestFocus();
      _sync(field);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      initialValue: _code,
      validator: widget.validator,
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: Semantics(
                label: widget.semanticsLabel,
                textField: true,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < widget.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      _buildBox(i, field),
                    ],
                  ],
                ),
              ),
            ),
            if (field.errorText != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: Text(
                  field.errorText!,
                  style: const TextStyle(color: ZadColors.errorText, fontSize: 12),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildBox(int i, FormFieldState<String> field) {
    return SizedBox(
      width: 56,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (node, event) => _onKey(i, event, field),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ZadColors.surface,
            borderRadius: BorderRadius.circular(ZadRadii.button),
          ),
          child: TextField(
            controller: _boxes[i],
            focusNode: _nodes[i],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ZadColors.ink,
            ),
            decoration: const InputDecoration(
              counterText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
            onChanged: (v) => _onChanged(i, v, field),
          ),
        ),
      ),
    );
  }
}
