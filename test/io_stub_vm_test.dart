import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/io_stub.dart' as io;
import 'package:test/test.dart';

void main() {
  test('io_stub.parseFlatFile throws UnsupportedError (VM import)', () async {
    expect(io.parseFlatFile('x'), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub.parseFlatFileSync throws UnsupportedError (VM import)', () {
    expect(() => io.parseFlatFileSync('x'), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub.parseFileWithIncludes throws UnsupportedError (VM import)',
      () async {
    expect(io.parseFileWithIncludes('x'), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub.writeFlat throws UnsupportedError (VM import)', () async {
    final doc = FlatDocument(const [FlatEntry('k', 'v')]);
    expect(io.writeFlat('x', doc), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub.writeFlatSync throws UnsupportedError (VM import)', () {
    final doc = FlatDocument(const [FlatEntry('k', 'v')]);
    expect(() => io.writeFlatSync('x', doc), throwsA(isA<UnsupportedError>()));
  });

  test('io_stub placeholder types are instantiable (VM import)', () {
    final a = io.FlatConfigIO();
    final b = io.FlatDocumentIO();
    expect(a, isA<io.FlatConfigIO>());
    expect(b, isA<io.FlatDocumentIO>());
  });

  group('Object extension stubs (VM import)', () {
    test('Object.parseFlat throws UnsupportedError', () async {
      expect(Object().parseFlat(), throwsA(isA<UnsupportedError>()));
    });

    test('Object.parseFlatSync throws UnsupportedError', () {
      expect(() => Object().parseFlatSync(), throwsA(isA<UnsupportedError>()));
    });

    test('Object.writeFlat throws UnsupportedError', () async {
      final doc = FlatDocument(const [FlatEntry('k', 'v')]);
      expect(Object().writeFlat(doc), throwsA(isA<UnsupportedError>()));
    });

    test('Object.writeFlatSync throws UnsupportedError', () {
      final doc = FlatDocument(const [FlatEntry('k', 'v')]);
      expect(
          () => Object().writeFlatSync(doc), throwsA(isA<UnsupportedError>()));
    });
  });
}
