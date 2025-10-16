import 'package:flatconfig/flatconfig.dart';

void main() {
  // A small, mixed example
  const cfg = r'''
# flags & numbers
enabled = true
retries = 3
timeout = 2.5s
backoff = 150ms
threshold = 0.75
bytes.si = 2MB
bytes.iec = 1MiB

# colors (CSS rrggbbaa and Flutter/Android aarrggbb)
color.css = #336699cc
color.argb = #cc336699
# #00ff88 (shorthand)
color.short = #0f8

# dates, duration, ratio, percent
when = 2024-12-31T23:59:59Z
aspect = 16:9
percent.a = 80%
percent.b = 0.4
percent.c = 12

# enums (freely mapped)
mode = FAST

# lists, sets, maps
list = a, b , c , , d
set = A, b, a, B
map = k1:v1, k2 : v2 , ignored, :novalue

# nested/mini document
mini = a=1, b = "text with = equals", c=
servers = host=a,port=8080 | host=b,port=9090 | invalid_no_equals

# url, uri-ish, json
endpoint = https://api.example.com/v1
json = {"k": [1,2,3], "ok": true}

# host:port (including IPv6)
hp1 = example.com:443
hp2 = [::1]:8080
hp3 = localhost
  ''';

  final doc = FlatConfig.parse(cfg);

  print('🔢 Booleans & numbers:');
  print(
      'enabled: ${doc.getBool("enabled")} (require: ${_try(() => doc.requireBool("enabled"))})');
  print(
      'retries: ${doc.getInt("retries")} (default: ${doc.getIntOr("missing", 42)})');
  print('threshold: ${doc.getDouble("threshold")}');

  print('\n⏱️ Duration:');
  print('timeout: ${doc.getDuration("timeout")}');
  print(
      'backoff: ${doc.getDuration("backoff")} (require: ${_try(() => doc.requireDuration("backoff"))})');

  print('\n📦 Bytes:');
  print('bytes.si:  ${doc.getBytes("bytes.si")} B');
  print('bytes.iec: ${doc.getBytes("bytes.iec")} B');

  print('\n🎨 Colors:');
  final css = doc.getHexColor('color.css', cssAlphaAtEnd: true);
  final argb = doc.getHexColor('color.argb', cssAlphaAtEnd: false);
  final short = doc.getHexColor('color.short');
  print('color.css  (CSS rrggbbaa → ARGB): 0x${css?.toRadixString(16)}');
  print('color.argb (AARRGGBB):            0x${argb?.toRadixString(16)}');
  print('color.short (#rgb):                0x${short?.toRadixString(16)}');
  print('color.css channels: ${doc.getColor("color.css")}');

  print('\n📅 Date, ratio, percent:');
  print(
      'when:     ${doc.getDateTime("when")} (require: ${_try(() => doc.requireDateTime("when"))})');
  print('aspect:   ${doc.getRatio("aspect")}');
  print('percent.a ${doc.getPercent("percent.a")}');
  print('percent.b ${doc.getPercent("percent.b")}');
  print('percent.c ${doc.getPercent("percent.c")}');

  print('\n🔠 Enums (mapping):');
  final modeMap = {
    'slow': 0,
    'normal': 1,
    'fast': 2,
  };
  print('mode: ${doc.getEnum("mode", modeMap, caseInsensitive: true)}');

  print('\n🧮 Lists, sets, maps:');
  print('list: ${doc.getListOrEmpty("list")}');
  print('set:  ${doc.getSetOrEmpty("set")}');
  print(
      'map:  ${doc.getMap("map")} (orEmpty: ${doc.getMapOrEmpty("missing")})');

  print('\n🧩 Mini document & list of docs:');
  final mini = doc.getDocument('mini');
  print('mini:\n${mini.toPrettyString(alignColumns: true)}');

  final servers = doc.getListOfDocuments('servers') ?? const [];
  for (var i = 0; i < servers.length; i++) {
    final s = servers[i];
    print('server[$i]: host=${s.getString("host")}, port=${s.getInt("port")}');
  }

  print('\n🔗 URI, JSON:');
  print(
      'endpoint: ${doc.getUri("endpoint")} (require: ${_try(() => doc.requireUri("endpoint"))})');
  print('json:     ${doc.getJson("json")}');

  print('\n🔌 Host:port:');
  print('hp1: ${doc.getHostPort("hp1")}');
  print('hp2: ${doc.getHostPort("hp2")}');
  print('hp3: ${doc.getHostPort("hp3")}');

  print('\n📏 Ranges, clamping, one-of, requireKeys:');
  print('retries in [0..5]: ${doc.getIntInRange("retries", min: 0, max: 5)}');
  print(
      'clamped retries to [5..1] (swapped): ${doc.getClampedInt("retries", min: 5, max: 1)}');
  print(
      'threshold in [0.5..1.0]: ${doc.getDoubleInRange("threshold", min: 0.5, max: 1.0)}');
  print('theme oneOf {dark,light}: ${doc.isOneOf("theme", {"dark", "light"})}');
  print('requireKeys: ${_try(() => doc.requireKeys([
            "enabled",
            "retries",
            "theme"
          ]))}');
}

/// Helper, to catch require*-calls in the example nicely.
String _try(Object? Function() f) {
  try {
    final v = f();
    return '$v';
  } on FormatException catch (e) {
    return 'ERROR($e)';
  }
}
