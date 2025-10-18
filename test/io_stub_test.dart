@TestOn('browser')
library io_stub_test;

import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/io_stub.dart' as io;
import 'package:test/test.dart';

void main() {
  test('parseFlatFile throws UnsupportedError on web/wasm', () async {
    expect(io.parseFlatFile('path'), throwsA(isA<UnsupportedError>()));
  });

  test('parseFlatFileSync throws UnsupportedError on web/wasm', () {
    expect(
      () => io.parseFlatFileSync('path'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('parseFileWithIncludes throws UnsupportedError on web/wasm', () async {
    expect(
      io.parseFileWithIncludes('path'),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('writeFlat throws UnsupportedError on web/wasm', () async {
    final doc = FlatDocument(const [FlatEntry('a', '1')]);
    expect(
      io.writeFlat('path', doc),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('writeFlatSync throws UnsupportedError on web/wasm', () {
    final doc = FlatDocument(const [FlatEntry('a', '1')]);
    expect(
      () => io.writeFlatSync('path', doc),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('placeholder namespace types exist', () {
    final ioNamespace = io.FlatConfigIO();
    final docNamespace = io.FlatDocumentIO();
    expect(ioNamespace, isA<io.FlatConfigIO>());
    expect(docNamespace, isA<io.FlatDocumentIO>());
  });

  group('Object extension stubs', () {
    test('parseFlat throws UnsupportedError', () async {
      expect(
        Object().parseFlat(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('parseFlatSync throws UnsupportedError', () {
      expect(
        () => Object().parseFlatSync(),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('writeFlat throws UnsupportedError', () async {
      final doc = FlatDocument(const [FlatEntry('k', 'v')]);
      expect(
        Object().writeFlat(doc),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('writeFlatSync throws UnsupportedError', () {
      final doc = FlatDocument(const [FlatEntry('k', 'v')]);
      expect(
        () => Object().writeFlatSync(doc),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
