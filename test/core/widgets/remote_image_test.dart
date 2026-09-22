import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zad/core/widgets/remote_image.dart';

/// Distinctive markers so we can tell the loading cue and the fallback apart
/// no matter how they are styled.
const _loading = Text('LOADING', key: Key('loading-marker'));
const _fallback = Text('FALLBACK', key: Key('fallback-marker'));

void main() {
  testWidgets('with no url, shows the fallback immediately — no network, no '
      'spinner', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteImage(url: null, placeholder: _fallback, loading: _loading),
        ),
      ),
    );

    expect(find.text('FALLBACK'), findsOneWidget);
    expect(find.text('LOADING'), findsNothing);
    expect(find.byType(CachedNetworkImage), findsNothing);
  });

  testWidgets('with a url, the spinner (not the fallback) is what shows while '
      'the image downloads', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteImage(
            url: 'https://example.test/banner.png',
            placeholder: _fallback,
            loading: _loading,
          ),
        ),
      ),
    );

    final cni = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final context = tester.element(find.byType(CachedNetworkImage));

    // The in-flight placeholder builder yields the loading cue — the fallback
    // artwork no longer flashes in before the real image paints.
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: cni.placeholder!(context, cni.imageUrl))),
    );
    expect(find.text('LOADING'), findsOneWidget);
    expect(find.text('FALLBACK'), findsNothing);
  });

  testWidgets('with a url, a failed load falls back to the placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteImage(
            url: 'https://example.test/banner.png',
            placeholder: _fallback,
            loading: _loading,
          ),
        ),
      ),
    );

    final cni = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final context = tester.element(find.byType(CachedNetworkImage));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: cni.errorWidget!(context, cni.imageUrl, Exception('404')),
        ),
      ),
    );
    expect(find.text('FALLBACK'), findsOneWidget);
    expect(find.text('LOADING'), findsNothing);
  });

  testWidgets('the default loading cue is a brand progress spinner', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RemoteImage(
            url: 'https://example.test/banner.png',
            placeholder: _fallback,
          ),
        ),
      ),
    );

    final cni = tester.widget<CachedNetworkImage>(
      find.byType(CachedNetworkImage),
    );
    final context = tester.element(find.byType(CachedNetworkImage));

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: cni.placeholder!(context, cni.imageUrl))),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
