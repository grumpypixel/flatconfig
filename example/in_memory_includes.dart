import 'package:flatconfig/flatconfig.dart';

void main() {
  // 1) Define your virtual "files"
  final resolver = MemoryIncludeResolver({
    'mem:base.conf': '''
app-name = MyApp
theme = dark
config-file = mem:colors.conf
''',
    'mem:colors.conf': '''
primary = mint
accent = teal
''',
    'mem:user.conf': '''
theme = light
username = guest
''',
  }, prefix: 'mem:');

  // 2) Your main document (also in memory)
  final mainText = '''
config-file = mem:base.conf
config-file = ?mem:user.conf
version = 1.2.3
''';

  // 3) Parse with resolver
  final doc = FlatConfigResolverIncludes.parseStringWithIncludes(
    mainText,
    resolver: resolver,
    originId: 'mem:main.conf',
  );

  print(doc['app-name']); // MyApp
  print(doc['theme']); // light (overridden by user)
  print(doc['primary']); // mint
  print(doc['accent']); // teal
  print(doc['version']); // 1.2.3
  print(doc['username']); // guest
}
