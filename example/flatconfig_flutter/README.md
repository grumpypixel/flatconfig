# flatconfig Flutter example

A Flutter web app whose appearance is decided entirely by a configuration file
shipped as an asset, and whose configuration is split across two of them
through an include.

Only web scaffolding is checked in. `flutter create --platforms=android,ios .`
adds the rest; nothing in the example depends on a platform.

## What it does

- reads `assets/config/app.conf` through `rootBundle`
- follows the `config-file` directives it finds, with an
  `AssetBundleIncludeResolver` — a bundle hands out its contents through a
  `Future`, which is the whole reason resolvers can be asynchronous
- applies `title`, `welcome-message`, `dark-mode`, `primary-color`,
  `background-color`, `padding` and `debug`
- lists the resolved key-value pairs on screen, so the effect of an include is
  visible rather than described

## The configuration

`app.conf` holds what the app is, and includes what it looks like:

```conf
title = Flatconfig Flutter
welcome-message = "Hello from assets via flatconfig!"
debug = true
padding = 20

config-file = theme.conf
config-file = ?user.conf
```

`theme.conf` holds the appearance, and nothing in the Dart code names its keys:

```conf
dark-mode = true
primary-color = f3d735
background-color = "#1a1a17"
```

`?user.conf` does not exist. The `?` marks it optional, so it contributes
nothing and no code has to handle its absence.

| Key | Type | Effect |
| --- | --- | --- |
| `title` | string | window title and `AppBar` title |
| `welcome-message` | string | header subtitle and welcome card |
| `dark-mode` | bool | light or dark `ColorScheme` |
| `primary-color` | hex colour | seeds `ColorScheme.fromSeed` |
| `background-color` | hex colour | `Scaffold` background |
| `padding` | int | outer content padding |
| `debug` | bool | shows Flutter's debug banner |

A hex colour is `RRGGBB` or `AARRGGBB`, with or without a leading `#`. The
package has no colour accessor — colour notation belongs to an application, not
to a configuration format — so `lib/main.dart` passes `parseHexColor` to
`getAsOr`. That function is what a converter looks like.

## Running it

```bash
cd example/flatconfig_flutter
flutter pub get
flutter run -d chrome
```

```bash
flutter build web                                  # static build
python3 -m http.server --directory build/web 8080  # and serve it
```

## Worth knowing

- **On the web there is no `dart:io`**, so `flatconfig_io.dart` cannot be
  imported. This example uses `flatconfig_includes.dart`, which is web-safe:
  includes work through a resolver, and the resolver here reads assets.
- **`rootBundle` caches** the future it returns, and each widget test runs in
  its own zone, so a second test awaiting a cached hit waits forever. The tests
  call `tearDown(rootBundle.clear)`. A missing asset is never cached, which is
  why only the positive cases hang without it.
- The example depends on the package through `path: ../../`, so it always
  builds against the working tree rather than a published version.
