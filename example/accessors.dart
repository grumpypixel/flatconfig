import 'package:flatconfig/flatconfig_accessors.dart';

void main() {
  const cfg = r'''
# flags & numbers
enabled = true
retries = 3
threshold = 0.75
timeout = 2.5s
backoff = 150ms

# lists
list = a, b , c , , d
hosts = alpha
hosts = beta

# dates, uris, json, enums
when = 2024-12-31T23:59:59Z
endpoint = https://api.example.com/v1
json = {"k": [1,2,3], "ok": true}
mode = FAST

# things the package deliberately does not parse for you
color = #336699cc
size = 2MB
  ''';

  final doc = FlatDocument.parse(cfg);

  // Every type follows the same three shapes: getX, getXOr, requireX.
  print('🔢 Core types:');
  print('  enabled:   ${doc.getBool('enabled')}');
  print('  retries:   ${doc.getInt('retries')}');
  print('  missing:   ${doc.getIntOr('missing', 42)} (default)');
  print('  threshold: ${doc.requireDouble('threshold')}');
  print('  list:      ${doc.getList('list')}');
  print('  absent:    ${doc.getListOr('absent', const ['fallback'])}');

  // A key can appear more than once; allAs converts every occurrence.
  print('\n🔁 Repeated keys:');
  print('  hosts:  ${doc.allAs('hosts', (v) => v.toUpperCase())}');
  print('  absent: ${doc.allAs('absent', (v) => v)} (null, not [])');

  // Dates, durations, URIs, JSON and enums live in flatconfig_accessors.dart.
  print('\n📦 Optional accessors:');
  print('  timeout:  ${doc.getDuration('timeout')}');
  print('  backoff:  ${doc.requireDuration('backoff')}');
  print('  when:     ${doc.getDateTime('when')}');
  print('  endpoint: ${doc.getUri('endpoint')}');
  print('  json:     ${doc.getJson('json')}');
  print(
    '  mode:     ${doc.getEnum('mode', const {'slow': 0, 'normal': 1, 'fast': 2})}',
  );

  // Anything else is a converter away. Colours and byte sizes used to ship
  // with the package; both are app-level decisions about notation, so they
  // are better written once, where the app can see them.
  print('\n🎨 Your own types, via getAs:');
  print('  color: 0x${doc.getAs('color', _parseArgb)?.toRadixString(16)}');
  print('  size:  ${doc.getAs('size', _parseBytes)} B');
  print(
    '  bad:   ${doc.getAsOr('color', _parseBytes, -1)} (converter said no)',
  );

  // require* reports which key and which value went wrong.
  print('\n💥 Failure reporting:');
  try {
    doc.requireInt('threshold');
  } on FormatException catch (e) {
    print('  $e');
  }
}

/// Parses `#RRGGBB` or `#RRGGBBAA` into a packed ARGB integer.
int _parseArgb(String value) {
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length != 6 && hex.length != 8) {
    throw FormatException('Expected RRGGBB or RRGGBBAA', value);
  }

  final n = int.parse(hex, radix: 16);
  if (hex.length == 6) {
    return 0xFF000000 | n;
  }

  // CSS puts alpha last; ARGB puts it first.
  return (n & 0xFF) << 24 | (n >> 8) & 0xFFFFFF;
}

/// Parses `2MB`, `1MiB` or a bare byte count.
int _parseBytes(String value) {
  final match = RegExp(
    r'^(\d+(?:\.\d+)?)\s*([kmgt]i?b?)?$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null) {
    throw FormatException('Expected a byte size', value);
  }

  final unit = (match.group(2) ?? '').toLowerCase();
  final base = unit.contains('i') ? 1024 : 1000;
  final power = switch (unit.isEmpty ? '' : unit[0]) {
    'k' => 1,
    'm' => 2,
    'g' => 3,
    't' => 4,
    _ => 0,
  };

  var factor = 1;
  for (var i = 0; i < power; i++) {
    factor *= base;
  }

  return (double.parse(match.group(1)!) * factor).round();
}
