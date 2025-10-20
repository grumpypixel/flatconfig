import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  test('empty root key with null: strict=true throws; strict=false keeps reset',
      () {
    expect(
      () => FlatConfig.fromMapData(
        {'': null},
        options: const FlatMapDataOptions(strict: true),
      ),
      throwsFormatException,
    );

    final doc = FlatConfig.fromMapData(
      {'': null},
      options: const FlatMapDataOptions(strict: false),
    );

    expect(doc.valuesOf(''), [null]);
    expect(doc[''], isNull);
  });
}
