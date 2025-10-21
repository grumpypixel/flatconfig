import 'package:flatconfig/flatconfig.dart';

void main() {
  final mem = MemoryIncludeResolver({
    'mem:i.conf': 'key = from-include\n',
  }, prefix: 'mem:');

  final text = '''
config-file = mem:i.conf
key = from-tail     # ignored, cannot override
new = ok            # allowed
''';

  final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
    text,
    resolver: mem,
    originId: 'mem:root',
  );

  print(doc['key']); // from-include
  print(doc['new']); // ok
}
