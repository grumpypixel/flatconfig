// Compile target proving that the web-safe libraries really are web-safe.
//
// `flatconfig.dart`, `flatconfig_includes.dart` and `flatconfig_accessors.dart`
// promise to work without `dart:io`. A promise like that is kept by the import
// graph, which is easy to break by adding one import three files deep, and a
// broken one is invisible on the VM. Compiling this file to JavaScript and to
// WASM is what turns it into something CI can fail on.
//
// `flatconfig_io.dart` is deliberately absent: it needs `dart:io` and is the
// one library a web program cannot have.
//
// The core library is reached through the re-exports rather than imported
// directly, since both barrels below export it.

import 'package:flatconfig/flatconfig_accessors.dart';
import 'package:flatconfig/flatconfig_includes.dart';

void main() {
  final doc = parseWithIncludesSync(
    'config-file = theme.conf\ntimeout = 30s\n',
    resolver: MemoryIncludeResolver(const {
      'theme.conf': 'background = 343028',
    }),
  );

  // Touch each library, so tree shaking cannot quietly drop one of them and
  // leave a dart:io import in the part that was removed.
  print(doc['background']);
  print(doc.requireDuration('timeout'));
  print(doc.withValue('background', 'ffaa00').encode());
  print(FlatDocument.fromData(const {'a': 1}).toMap());
}
