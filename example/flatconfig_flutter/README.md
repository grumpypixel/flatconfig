# flatconfig Flutter Example

This example shows how to use `flatconfig` in a Flutter app (web, mobile, desktop). It loads a flat configuration file from assets and uses it to drive theme, layout, and UI elements, then lists the active key=value pairs.

## What it does

- Loads `assets/config/app.conf` via `rootBundle`
- Parses using `FlatConfig.parse`
- Applies optional keys: `title`, `welcome-message`, `dark-mode`, `primary-color`, `background-color`, `padding`
- Renders a Material 3 UI seeded by `primary-color`
- Displays all latest key=value pairs from `config.toMap()`

## Configuration keys

- `title` (string): App/window title and `AppBar` title
- `welcome-message` (string): Header subtitle and welcome card text
- `dark-mode` (bool): Toggles light/dark theme
- `primary-color` (hex color like `#6750A4`): Seeds `ColorScheme.fromSeed`
- `background-color` (hex color like `#F6F2FF`): `Scaffold` background color
- `padding` (int): Outer content padding in logical pixels
- `debug` (bool, optional): Read from config, currently not used in UI

## Relevant files

- `lib/main.dart` – loads/parses config and renders the UI
- `assets/config/app.conf` – example configuration
- `pubspec.yaml` – adds the local `flatconfig` path dependency and registers the asset

## Run

```bash
cd example/flatconfig_flutter
flutter pub get
flutter run
```

Run on a specific target (examples): `-d chrome | android | ios | macos | linux | windows`

Build for static hosting (web):

```bash
flutter build web
```

Serve the built app locally (optional):

```bash
python3 -m http.server --directory build/web 8080
# then open http://localhost:8080
```

## Edit the configuration

Change values in `assets/config/app.conf`, e.g.:

```conf
title = Flatconfig Flutter
welcome-message = "Hello from assets via flatconfig!"
dark-mode = false
primary-color = #6750A4
background-color = #F6F2FF
padding = 20
# debug = false
```

### Notes

- Runs on web, mobile, and desktop. This example reads config from bundled assets via `rootBundle`.
- On web, file-based includes and `dart:io` APIs are not available. Use `FlatConfig.parse` on strings (assets or HTTP responses).
- Hex color values must include the leading `#`.
- The example depends on the local package via `path: ../../` in `pubspec.yaml`.
