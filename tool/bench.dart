import 'dart:async';
import 'dart:io';
import 'package:flatconfig/flatconfig.dart';
import 'package:flatconfig/src/io.dart' as io;

void main(List<String> args) async {
  final iterations = args.isNotEmpty ? int.parse(args[0]) : 1000;
  final entries = args.length >= 2 ? int.parse(args[1]) : 10000;
  final repeats = args.length >= 3 ? int.parse(args[2]) : 7;

  final sample = _generateSample(entries);
  final file = File('tool/tmp_bench.conf')..writeAsStringSync(sample);

  // Warmup: JIT to temperature
  for (var i = 0; i < 5; i++) {
    final d = FlatConfig.parse(sample);
    d.encode();
    d.whereKey('k0').toList();
    d.whereKeys(['k0', 'k1', 'k2']).toList();
    d.whereValue('v0').toList();
    d.keys.toList();
    d.has('k0');
    d.firstValueOf('k0');
    d.valuesOf('k0');
    d.getInt('k0');
    d.getBool('k0');
    d.getDouble('k0');
  }

  // Test-fixture data
  final doc = FlatConfig.parse(sample);
  final bytes = file.readAsBytesSync();

  // Small helper documents for getDocument/getListOfDocuments/getHexColor
  final docPairs = FlatConfig.fromMap({
    'mini': r'a=1, b = "x = y", c=, d = " spaced "',
  });
  final docListOfDocs = FlatConfig.fromMap({
    'servers': r'host=a,port=1 | host=b,port=2 | note="x = y"',
  });
  final docColors = FlatConfig.fromMap({
    'cRgb': '#123',
    'cRgba': '#1234',
    'cRrGgBb': '#112233',
    'cAaRrGgBb': '#80112233',
    'cRrGgBbAa': '#11223380',
  });

  // Baseline (Loop-Overhead) for Sync-Benches
  final baseline = _measureSync(
    label: 'baseline',
    iterations: iterations,
    repeats: repeats,
    body: () {
      // Mini-Work, so that the loop is not noop
      _sink ^= 1;
    },
  );

  print('--- FlatConfig Bench ---');
  print('entries=$entries, iterations=$iterations, repeats=$repeats');
  print('');

  // Sync-Benches (subtract baseline)
  _printStats(_measureSync(
    label: 'parse(String)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final d = FlatConfig.parse(sample);
      _sink ^= d.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'encode(Document, default)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final s = doc.encode();
      _sink ^= s.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'encode(Document, escaped+alwaysQuote)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final s = doc.encode(
        options: const FlatEncodeOptions(
          escapeQuoted: true,
          alwaysQuote: true,
        ),
      );
      _sink ^= s.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'whereKey("k0").toList()',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final l = doc.whereKey('k0').toList();
      _sink ^= l.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'whereKeys(5 items).toList()',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final l = doc.whereKeys(['k0', 'k1', 'k2', 'k3', 'k4']).toList();
      _sink ^= l.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'whereValue("v0").toList()',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final l = doc.whereValue('v0').toList();
      _sink ^= l.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'keys.toList()',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final l = doc.keys.toList();
      _sink ^= l.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'has("k0")',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final b = doc.has('k0');
      _sink ^= b ? 1 : 0;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'firstValueOf("k0")',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final s = doc.firstValueOf('k0');
      _sink ^= (s?.length ?? 0);
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'valuesOf("k0")',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final l = doc.valuesOf('k0');
      _sink ^= l.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'getInt("k0") / getBool / getDouble',
    iterations: iterations,
    repeats: repeats,
    body: () {
      _sink ^= (doc.getInt('k0') ?? 0);
      _sink ^= (doc.getBool('k0') == true ? 1 : 0);
      _sink ^= (doc.getDouble('k0')?.toInt() ?? 0);
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'collapse()',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final d = doc.collapse();
      _sink ^= d.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'getDocument("mini")',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final sub = docPairs.getDocument('mini');
      _sink ^= sub.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'getListOfDocuments("servers")',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final list = docListOfDocs.getListOfDocuments('servers') ?? const [];
      _sink ^= list.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'getHexColor(AA at end, cssAlphaAtEnd=true)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      _sink ^= (docColors.getHexColor('cRrGgBbAa', cssAlphaAtEnd: true) ?? 0);
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'getHexColor(AA at front, cssAlphaAtEnd=false)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      _sink ^= (docColors.getHexColor('cAaRrGgBb', cssAlphaAtEnd: false) ?? 0);
    },
  ).minus(baseline));

  // Async-Benches (separate; subtracting baseline is less meaningful)
  print('');
  _printStats(await _measureAsync(
    label: 'parse(File.parseFlat)',
    iterations: iterations,
    repeats: repeats,
    body: () async {
      final d = await io.parseFlatFile(file.path);
      _sink ^= d.length;
    },
  ));

  _printStats(await _measureAsync(
    label: 'parseFromByteStream(Stream.value(bytes))',
    iterations: iterations,
    repeats: repeats,
    body: () async {
      final d = await FlatConfig.parseFromByteStream(Stream.value(bytes));
      _sink ^= d.length;
    },
  ));

  _printStats(await _measureAsync(
    label: 'parseEntries(file.openRead()) [stream]',
    iterations: iterations,
    repeats: repeats,
    body: () async {
      var c = 0;
      await for (final e in FlatConfig.parseEntries(file.openRead())) {
        c ^= (e.value?.length ?? 0);
      }
      _sink ^= c;
    },
  ));

  // Includes benches (cold vs. warm cache)
  final incDir = await Directory.systemTemp.createTemp('flatconfig_bench_inc_');
  final mainInc = File('${incDir.path}/main.conf')..writeAsStringSync('''
# main
app = bench
config-file = theme.conf
config-file = features.conf
tail = after
''');
  File('${incDir.path}/theme.conf').writeAsStringSync('''
theme = dark
config-file = colors.conf
''');
  File('${incDir.path}/colors.conf').writeAsStringSync('''
background = 343028
foreground = ffffff
''');
  File('${incDir.path}/features.conf').writeAsStringSync('''
feature-a = on
feature-b = off
''');

  _printStats(await _measureAsync(
    label: 'parseWithIncludes (cold)',
    iterations: iterations,
    repeats: repeats,
    body: () async {
      final d = await FlatConfigIncludes.parseWithIncludes(mainInc,
          cache: <String, FlatDocument>{});
      _sink ^= d.length;
    },
  ));

  final includesCache = <String, FlatDocument>{};
  _printStats(await _measureAsync(
    label: 'parseWithIncludes (warm cache)',
    iterations: iterations,
    repeats: repeats,
    body: () async {
      final d = await FlatConfigIncludes.parseWithIncludes(mainInc,
          cache: includesCache);
      _sink ^= d.length;
    },
  ));

  // Cleanup includes temp directory
  try {
    await incDir.delete(recursive: true);
  } on PathNotFoundException {
    // ignore
  }

  // Strict vs. Lax
  final strictSample = '# ok\nonlykey\nk = v\n';
  _printStats(_measureSync(
    label: 'parse(String, lax)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      final d = FlatConfig.parse(
        strictSample,
        options: const FlatParseOptions(strict: false),
      );
      _sink ^= d.length;
    },
  ).minus(baseline));

  _printStats(_measureSync(
    label: 'parse(String, strict)',
    iterations: iterations,
    repeats: repeats,
    body: () {
      try {
        final d = FlatConfig.parse(
          strictSample,
          options: const FlatParseOptions(strict: true),
        );
        _sink ^= d.length; // will not be reached
      } catch (_) {
        _sink ^= 1; // error path is counted
      }
    },
  ).minus(baseline));

  // Prevents the compiler from optimizing "everything" away
  stdout.writeln('\n(ignore) sink=$_sink');
}

/// Global blackhole variable
int _sink = 0;

/// Result values of a benchmark (µs)
class BenchStats {
  BenchStats(this.label, this.micros, this.iterations);
  final String label;
  final List<int> micros; // per Repeat
  final int iterations;

  int get best => micros.reduce((a, b) => a < b ? a : b);
  double get median {
    final sorted = [...micros]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid].toDouble();
    }

    return (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  double get medianPerIter => median / iterations;
  double get bestPerIter => best / iterations;

  double get opsPerSecMedian => iterations / (median / 1e6);
  double get opsPerSecBest => iterations / (best / 1e6);

  BenchStats minus(BenchStats baseline) {
    if (baseline.micros.length != micros.length) {
      return this;
    }
    final adjusted = <int>[];
    for (var i = 0; i < micros.length; i++) {
      final v = micros[i] - baseline.micros[i];
      adjusted.add(v < 0 ? 0 : v);
    }

    return BenchStats(label, adjusted, iterations);
    // (ops/s recalculated based on adjusted times)
  }
}

void _printStats(BenchStats s) {
  stdout.writeln(
      '${s.label.padRight(42)} median=${s.median.toStringAsFixed(0)}µs '
      '(${s.medianPerIter.toStringAsFixed(1)}µs/iter, '
      '${s.opsPerSecMedian.toStringAsFixed(1)} ops/s)   '
      'best=${s.best}µs '
      '(${s.bestPerIter.toStringAsFixed(1)}µs/iter, '
      '${s.opsPerSecBest.toStringAsFixed(1)} ops/s)');
}

BenchStats _measureSync({
  required String label,
  required int iterations,
  required int repeats,
  required void Function() body,
}) {
  final times = <int>[];
  for (var r = 0; r < repeats; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      body();
    }
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }

  return BenchStats(label, times, iterations);
}

Future<BenchStats> _measureAsync({
  required String label,
  required int iterations,
  required int repeats,
  required Future<void> Function() body,
}) async {
  final times = <int>[];
  for (var r = 0; r < repeats; r++) {
    final sw = Stopwatch()..start();
    for (var i = 0; i < iterations; i++) {
      await body();
    }
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }

  return BenchStats(label, times, iterations);
}

String _generateSample(int n) {
  final buf = StringBuffer();
  for (var i = 0; i < n; i++) {
    if (i % 10 == 0) {
      buf.writeln('# comment');
    }
    if (i % 13 == 0) {
      buf.writeln('onlykey'); // invalid line (no '=')
    }
    if (i % 7 == 0) {
      buf.writeln('k$i = " value $i with spaces "');
    } else if (i % 5 == 0) {
      buf.writeln('k$i = ');
    } else {
      buf.writeln('k$i = v$i');
    }
  }

  return buf.toString();
}
