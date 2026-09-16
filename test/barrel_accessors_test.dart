/// Imports nothing but the accessor barrel, which re-exports the core.
library barrel_accessors_test;

import 'package:flatconfig/flatconfig_accessors.dart';
import 'package:test/test.dart';

enum _Theme { dark, light }

const _themes = {'dark': _Theme.dark, 'light': _Theme.light};

void main() {
  test('the optional accessors are reachable, in all three shapes', () {
    final doc = FlatDocument.parse('''
when = 2024-03-01
timeout = 30s
home = https://example.com
limits = {"max": 3}
theme = dark
''');

    expect(doc.getDateTime('when'), DateTime.parse('2024-03-01'));
    expect(doc.getDuration('timeout'), const Duration(seconds: 30));
    expect(doc.requireUri('home').host, 'example.com');
    expect(doc.getJson('limits'), const {'max': 3});
    expect(doc.getEnum('theme', _themes), _Theme.dark);

    expect(doc.getDateTimeOr('nope', DateTime.utc(2000)), DateTime.utc(2000));
    expect(doc.getDurationOr('nope', Duration.zero), Duration.zero);
    expect(doc.getUriOr('nope', Uri.parse('about:blank')).scheme, 'about');
    expect(doc.getJsonOr('nope', const <String, Object?>{}), isEmpty);
    expect(doc.getEnumOr('nope', _themes, _Theme.light), _Theme.light);

    expect(() => doc.requireDuration('nope'), throwsFormatException);
  });

  test('the core is re-exported, so one import is enough', () {
    expect(FlatDocument.parse('a = 1\n').requireInt('a'), 1);
  });
}
