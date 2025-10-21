import 'dart:io';

import 'package:flatconfig/flatconfig.dart';
import 'package:path/path.dart' as p;

Future<void> main() async {
  final temp = await Directory.systemTemp.createTemp('flatconfig_demo_');
  try {
    final base = File(p.join(temp.path, 'base.conf'))
      ..writeAsStringSync('name = Base\nconfig-file = colors.conf\n');
    File(p.join(temp.path, 'colors.conf'))
        .writeAsStringSync('primary = blue\n');

    final mem = MemoryIncludeResolver({
      'mem:hotfix.conf': 'primary = mint\n',
    }, prefix: 'mem:');

    // Order defines resolution priority (first hit wins)
    final resolver = CompositeIncludeResolver([
      FileIncludeResolver(),
      mem,
    ]);

    final text = '''
config-file = ${base.path}
config-file = mem:hotfix.conf
''';

    final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
      text,
      resolver: resolver,
      originId: p.join(temp.path, 'virtual_main.conf'),
    );

    print(doc['name']); // Base (from file)
    print(doc['primary']); // mint (from later in-memory include)
  } finally {
    await temp.delete(recursive: true);
  }
}
