@TestOn('browser')
library includes_stub_test;

import 'package:flatconfig/src/includes_stub.dart' as inc;
import 'package:flatconfig/src/io_stub.dart';
import 'package:test/test.dart';

void main() {
  group('FlatConfigIncludes (web/wasm stubs)', () {
    test('parseWithIncludes throws UnsupportedError', () async {
      expect(
        inc.FlatConfigIncludes.parseWithIncludes(Object()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseWithIncludesSync throws UnsupportedError', () {
      expect(
        () => inc.FlatConfigIncludes.parseWithIncludesSync(Object()),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseWithIncludesFromPath throws UnsupportedError', () async {
      expect(
        inc.FlatConfigIncludes.parseWithIncludesFromPath('path'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseWithIncludesFromPathSync throws UnsupportedError', () {
      expect(
        () => inc.FlatConfigIncludes.parseWithIncludesFromPathSync('path'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  test('FileIncludes placeholder type is constructible', () {
    final f = inc.FileIncludes(Object());
    expect(f, isA<inc.FileIncludes>());
  });

  group('Object extension includes stubs', () {
    test('parseWithIncludes on Object throws UnsupportedError', () async {
      expect(
        Object().parseWithIncludes(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseWithIncludesSync on Object throws UnsupportedError', () {
      expect(
        () => Object().parseWithIncludesSync(),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
