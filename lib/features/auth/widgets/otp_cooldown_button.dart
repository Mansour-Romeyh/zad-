import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/api/api_exceptions.dart';
import '../../../core/theme.dart';
import '../../../l10n/app_localizations.dart';

/// Resend button with a per-second cooldown countdown, shared by
/// [OtpPage]'s registration flow and the reset-password OTP step. Honors
/// the server's `cooldown_sec` (HTTP 423 `OtpCooldownException`, or the
/// `cooldown_sec` returned alongside a successful resend).
class OtpCooldownButton extends StatefulWidget {
  const OtpCooldownButton({
    required this.initialCooldownSec,
    required this.onResend,
    this.onError,
    super.key,
  });

  /// Seconds to count down from before resend is enabled.
  final int initialCooldownSec;

  /// Requests a fresh OTP; returns the new cooldown to count down from.
  final Future<int> Function() onResend;

  /// Called instead of throwing when [onResend] fails, so the composing
  /// screen can surface it (e.g. via `AuthErrorBanner`) without an
  /// unhandled async error.
  final void Function(Object error)? onError;

  @override
  State<OtpCooldownButton> createState() => _OtpCooldownButtonState();
}

class _OtpCooldownButtonState extends State<OtpCooldownButton> {
  late int _remaining;
  Timer? _timer;
  bool _resending = false;

  @override
  void initState() {
    super.initState();
    _remaining = widget.initialCooldownSec;
    _startTimerIfNeeded();
  }

  void _startTimerIfNeeded() {
    _timer?.cancel();
    if (_remaining <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remaining -= 1;
        if (_remaining <= 0) {
          _remaining = 0;
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _handleResend() async {
    setState(() => _resending = true);
    try {
      final cooldown = await widget.onResend();
      if (!mounted) return;
      setState(() {
        _remaining = cooldown;
        _resending = false;
      });
      _startTimerIfNeeded();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        // A 423 means the server is still inside its cooldown window —
        // re-arm the countdown with the server-provided remainder so the
        // button isn't immediately tappable again.
        if (e is OtpCooldownException) _remaining = e.cooldownSec;
      });
      _startTimerIfNeeded();
      widget.onError?.call(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final canResend = _remaining <= 0 && !_resending;
    return TextButton(
      onPressed: canResend ? _handleResend : null,
      child: Text(
        canResend ? l10n.authResendCode : l10n.authResendIn(_remaining),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: canResend ? ZadColors.primary : ZadColors.muted,
        ),
      ),
    );
  }
}
