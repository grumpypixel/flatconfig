import 'package:flatconfig/flatconfig_includes.dart';
import 'package:flatconfig_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

/// What the example is actually for: a configuration file shipped as an asset
/// decides what the app looks like, and it may be split across several assets.

void main() {
  // The resolver tests read the bundle outside testWidgets, which is where the
  // binding would otherwise still be missing and rootBundle would never answer.
  TestWidgetsFlutterBinding.ensureInitialized();

  // rootBundle caches the future it hands out, and each test runs in its own
  // zone, so a second test awaiting the cached future waits forever. Only a
  // hit is affected: a missing asset is never cached, which is why the
  // negative cases here passed while the positive ones hung.
  tearDown(rootBundle.clear);

  testWidgets('the app takes its title from the asset', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // assets/config/app.conf sets this, and nothing in the code does.
    expect(find.text('Flatconfig Flutter'), findsWidgets);
    expect(
      find.text('Hello from assets via flatconfig!'),
      findsWidgets,
      reason: 'the quoted value is unquoted before it reaches the widget',
    );
  });

  testWidgets('the included asset reaches the screen', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    // Only assets/config/theme.conf sets this, and it arrives through the
    // include directive in app.conf.
    expect(find.textContaining('primary-color = f3d735'), findsOneWidget);
  });

  group('AssetBundleIncludeResolver', () {
    final resolver = AssetBundleIncludeResolver(rootBundle);

    test('reads an asset that exists', () async {
      final unit = await resolver.resolve(
        const IncludeRequest('theme.conf', fromId: 'app.conf'),
      );

      expect(unit, isNotNull);
      expect(unit!.id, 'assets/config/theme.conf');
      expect(unit.content, contains('primary-color'));
    });

    test('answers nothing for an asset that does not exist', () async {
      // Not an error: the `?` marker on the directive decides that, which is
      // why the resolver neither throws nor needs to know about the marker.
      expect(
        await resolver.resolve(
          const IncludeRequest('nope.conf', fromId: 'app.conf'),
        ),
        isNull,
      );
    });

    test('a missing optional include leaves the rest intact', () async {
      final doc = await parseWithIncludes(
        'a = 1\nconfig-file = ?nope.conf\nconfig-file = theme.conf\n',
        resolver: resolver,
        originId: 'assets/config/app.conf',
      );

      expect(doc['a'], '1');
      expect(doc['primary-color'], 'f3d735');
    });

    test('a missing required include throws', () async {
      expect(
        () => parseWithIncludes(
          'config-file = nope.conf\n',
          resolver: resolver,
          originId: 'assets/config/app.conf',
        ),
        throwsA(isA<MissingIncludeException>()),
      );
    });
  });

  group('parseHexColor', () {
    test('reads six digits as opaque', () {
      expect(parseHexColor('f3d735'), const Color(0xFFF3D735));
      expect(parseHexColor('#f3d735'), const Color(0xFFF3D735));
    });

    test('reads eight digits as given', () {
      expect(parseHexColor('80f3d735'), const Color(0x80F3D735));
    });

    test('rejects anything else', () {
      for (final raw in const ['', 'f3d73', 'zzzzzz', 'f3d7355', 'blue']) {
        expect(
          () => parseHexColor(raw),
          throwsFormatException,
          reason: 'should reject "$raw"',
        );
      }
    });

    test('getAs turns a rejection into a fallback', () {
      final doc = FlatDocument.parse('a = nonsense\n');

      expect(doc.getAs('a', parseHexColor), isNull);
      expect(doc.getAsOr('a', parseHexColor, Colors.blue), Colors.blue);
      expect(doc.getAsOr('missing', parseHexColor, Colors.blue), Colors.blue);
    });
  });
}
