import 'package:test/test.dart';

import 'package:flatconfig/src/includes_stub.dart' as inc;

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
}
