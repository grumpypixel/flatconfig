import 'package:flatconfig/flatconfig_includes.dart';

void main() {
  final mem = MemoryIncludeResolver({
    'mem:i.conf': 'key = from-include\n',
  }, prefix: 'mem:');

  final text = '''
config-file = mem:i.conf
# Ignored: an include already set this key.
key = from-tail

# Allowed: no include mentions it.
new = ok
''';

  final doc = parseWithIncludesSync(text, resolver: mem, originId: 'mem:root');

  print(doc['key']); // from-include
  print(doc['new']); // ok
}
