import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flatconfig/flatconfig.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FlatDocument>(
      future: _loadConfigFromAssets(),
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
        final seedHex = config.getHexColor('primary-color');
        final seedColor = seedHex != null ? Color(seedHex) : Colors.blue;
        final debug = config.getBoolOr('debug', false);

        return AppScope(
          config: config,
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

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.config, required super.child});

  final FlatDocument config;

  static AppScope of(BuildContext context) {
    final AppScope? scope = context
        .dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope.of() called with no AppScope in context.');

    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) {
    return !identical(config, oldWidget.config);
  }
}

class ConfigHome extends StatelessWidget {
  const ConfigHome({super.key});

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).config;
    final padding = config.getIntOr('padding', 16).toDouble();
    final welcome = config.getStringOr('welcome-message', 'Hello from assets!');
    final bgHex = config.getHexColor('background-color');
    final backgroundColor = bgHex != null
        ? Color(bgHex)
        : Theme.of(context).colorScheme.surface;
    final seedHex = config.getHexColor('primary-color');
    final seedColor = seedHex != null
        ? Color(seedHex)
        : Theme.of(context).colorScheme.primary;

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
                color: onPrimary.withOpacity(0.9),
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
  final content = await rootBundle.loadString('assets/config/app.conf');
  return FlatConfig.parse(
    content,
    options: const FlatParseOptions(strict: false, decodeEscapesInQuoted: true),
  );
}

String _formatLatest(FlatDocument doc) {
  final latest = doc.toMap();
  if (latest.isEmpty) return '<empty>';
  return latest.entries
      .map((e) => '${e.key} = ${e.value ?? '<null>'}')
      .join('\n');
}
