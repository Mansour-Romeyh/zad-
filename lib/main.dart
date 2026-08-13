import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/api/dns_fallback.dart';
import 'core/push/fcm_push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Chrome-style DNS resilience: when the device's own resolver can't
  // resolve a hostname (broken ISP DNS), fall back to DNS-over-HTTPS, and
  // as a last resort to a build-time IP pin — some carriers null-route the
  // public DoH resolvers too. TLS always validates the hostname's cert, so
  // the pin can't be abused. Covers Dio and Image.network alike.
  HttpOverrides.global = DnsFallbackHttpOverrides(
    resolver: DohResolver(
      staticFallbacks: const {
        // Production backend (Hetzner, 2026-07). Update if the server moves.
        'zad.micronext.net': ['91.98.78.28'],
      },
    ),
  );
  // FCM-backed when this build carries Firebase config, noop otherwise.
  final pushService = await initPushService();
  runApp(ZadApp(pushService: pushService));
}
