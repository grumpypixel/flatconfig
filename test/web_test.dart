@TestOn('browser')
library web_test;

import 'package:flatconfig/flatconfig_accessors.dart';
import 'package:flatconfig/flatconfig_includes.dart';
import 'package:test/test.dart';

void main() {
  test('core parsing works on web', () {
    final doc = FlatDocument.parse('a = 1\n');
    expect(doc.getInt('a'), 1);
  });

  test('includes work on web, through a resolver', () {
    final doc = parseWithIncludesSync(
      'config-file = theme.conf\nfont-size = 14\n',
      resolver: MemoryIncludeResolver({'theme.conf': 'background = 343028\n'}),
    );

    expect(doc['background'], '343028');
    expect(doc.requireInt('font-size'), 14);
  });

  test('the optional accessors work on web', () {
    final doc = FlatDocument.parse('timeout = 30s\n');

    expect(doc.requireDuration('timeout'), const Duration(seconds: 30));
  });
}
