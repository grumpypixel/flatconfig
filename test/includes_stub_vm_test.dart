import 'package:flatconfig/src/includes_stub.dart' as inc;
import 'package:test/test.dart';

void main() {
  test('includes_stub parseWithIncludes throws (VM import)', () async {
    expect(
      inc.FlatConfigIncludes.parseWithIncludes(Object()),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('includes_stub parseWithIncludesSync throws (VM import)', () {
    expect(
      () => inc.FlatConfigIncludes.parseWithIncludesSync(Object()),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('includes_stub path variants throw (VM import)', () async {
    expect(
      inc.FlatConfigIncludes.parseWithIncludesFromPath('p'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(
      () => inc.FlatConfigIncludes.parseWithIncludesFromPathSync('p'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('FileIncludes placeholder is constructible (VM import)', () {
    final f = inc.FileIncludes(Object());
    expect(f, isA<inc.FileIncludes>());
  });

  group('Object extension include stubs (VM import)', () {
    test('Object.parseWithIncludes throws UnsupportedError', () async {
      expect(Object().parseWithIncludes(), throwsA(isA<UnsupportedError>()));
    });

    test('Object.parseWithIncludesSync throws UnsupportedError', () {
      expect(() => Object().parseWithIncludesSync(),
          throwsA(isA<UnsupportedError>()));
    });
  });
}
