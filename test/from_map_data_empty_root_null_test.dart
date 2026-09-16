import 'package:flatconfig/flatconfig.dart';
import 'package:test/test.dart';

void main() {
  test(
    'empty root key with null: strict=true throws; strict=false drops it',
    () {
      expect(
        () => FlatConfig.fromMapData({
          '': null,
        }, options: const FlatMapDataOptions(strict: true)),
        throwsFormatException,
      );

      // An empty key has no wire form, so there is nothing to keep. It used to
      // survive here and then vanish on encode (SPEC.md 3).
      final doc = FlatConfig.fromMapData({
        '': null,
      }, options: const FlatMapDataOptions(strict: false));

      expect(doc, isEmpty);
      expect(doc.allValues(''), isEmpty);
    },
  );
}
