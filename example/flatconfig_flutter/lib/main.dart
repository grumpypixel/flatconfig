import 'package:flatconfig/flatconfig_includes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

/// Reads a colour written as `RRGGBB`, `AARRGGBB`, or either with a leading
/// `#`, and throws on anything else.
///
/// The core accessors stop at the types the format itself has: strings,
/// numbers, booleans and lists. Everything past that is a converter handed to
/// `getAs`, and this is what one looks like. `getAs` turns a thrown
/// [FormatException] into `null`, so the caller sees one missing-or-unreadable
/// case rather than two.
Color parseHexColor(String raw) {
  final hex = raw.startsWith('#') ? raw.substring(1) : raw;
  final value = int.tryParse(hex, radix: 16);

  if (value == null || (hex.length != 6 && hex.length != 8)) {
    throw FormatException('Not a hex colour', raw);
  }

  return Color(hex.length == 6 ? 0xFF000000 | value : value);
}

/// Resolves `config-file` directives against the asset bundle.
///
/// A bundle hands out its contents through a [Future], which is the whole
/// reason [IncludeResolver] is asynchronous: a synchronous resolver cannot be
/// written against one at all.
final class AssetBundleIncludeResolver implements IncludeResolver {
  /// Resolves targets as paths under [directory] of [bundle].
  const AssetBundleIncludeResolver(
    this.bundle, {
    this.directory = 'assets/config',
  });

  /// The bundle to read from.
  final AssetBundle bundle;

  /// The directory a directive's target is relative to.
  final String directory;

  @override
  Future<IncludeUnit?> resolve(IncludeRequest request) async {
    final key = '$directory/${request.target}';

    try {
      return IncludeUnit(id: key, content: await bundle.loadString(key));
    } on FlutterError {
      // Not in the bundle. Whether that is an error is the directive's
      // decision, through its `?` marker, not the resolver's.
      return null;
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  /// Started once, on first build.
  ///
  /// Calling the loader inside [build] would start a fresh read of the bundle
  /// on every rebuild — and the app rebuilds whenever the platform brightness,
  /// the text scale or the window size changes.
  late final Future<FlatDocument> _config = _loadConfigFromAssets();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FlatDocument>(
      future: _config,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return MaterialApp(
            home: Scaffold(
              body: Center(
                child: Text('Failed to load config: ${snapshot.error}'),
              ),
            ),
          );
        }

        final config = snapshot.data!;
        final appTitle = config.getStringOr('title', 'Flatconfig Demo');
        final isDark = config.getBoolOr('dark-mode', false);
        final seedColor = config.getAsOr(
          'primary-color',
          parseHexColor,
          Colors.blue,
        );
        final debug = config.getBoolOr('debug', false);

        return ChangeNotifierProvider(
          create: (_) => ConfigProvider(config),
          child: MaterialApp(
            debugShowCheckedModeBanner: debug,
            title: appTitle,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: seedColor,
                brightness: isDark ? Brightness.dark : Brightness.light,
              ),
              useMaterial3: true,
            ),
            home: const ConfigHome(),
          ),
        );
      },
    );
  }
}

class ConfigProvider extends ChangeNotifier {
  ConfigProvider(this._config);

  FlatDocument _config;

  FlatDocument get config => _config;

  void updateConfig(FlatDocument newConfig) {
    _config = newConfig;
    notifyListeners();
  }
}

class ConfigHome extends StatelessWidget {
  const ConfigHome({super.key});

  @override
  Widget build(BuildContext context) {
    final config = Provider.of<ConfigProvider>(context).config;
    final padding = config.getIntOr('padding', 16).toDouble();
    final welcome = config.getStringOr('welcome-message', 'Hello from assets!');
    final backgroundColor = config.getAsOr(
      'background-color',
      parseHexColor,
      Theme.of(context).colorScheme.surface,
    );
    final seedColor = config.getAsOr(
      'primary-color',
      parseHexColor,
      Theme.of(context).colorScheme.primary,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(config.getStringOr('title', 'Flatconfig Demo')),
      ),
      backgroundColor: backgroundColor,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _Header(
            title: config.getStringOr('title', 'Flatconfig Demo'),
            subtitle: welcome,
            seed: seedColor,
          ),
          Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoCard(
                  icon: Icons.info_outline,
                  title: 'Welcome',
                  body: welcome,
                ),
                const SizedBox(height: 12),
                _InfoCard(
                  icon: Icons.tune,
                  title: 'Active configuration',
                  body: _formatLatest(config),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.seed,
  });
  final String title;
  final String subtitle;
  final Color seed;

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    final secondary = Theme.of(context).colorScheme.secondary;
    final gradEnd = Color.lerp(seed, secondary, 0.35) ?? seed;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [seed, gradEnd],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: onPrimary.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<FlatDocument> _loadConfigFromAssets() async {
  const root = 'assets/config/app.conf';

  return parseWithIncludes(
    await rootBundle.loadString(root),
    resolver: AssetBundleIncludeResolver(rootBundle),
    originId: root,
  );
}

String _formatLatest(FlatDocument doc) {
  final latest = doc.toMap();
  if (latest.isEmpty) return '<empty>';
  return latest.entries
      .map((e) => '${e.key} = ${e.value ?? '<null>'}')
      .join('\n');
}
