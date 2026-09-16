import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the example is actually for: a configuration file shipped as an asset
/// decides what the app looks like.

void main() {
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
