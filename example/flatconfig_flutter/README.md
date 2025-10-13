### flatconfig Flutter Web Example

This example shows how to use `flatconfig` in a Flutter web app. It loads a flat configuration file from assets and uses it to drive theme and UI elements, then lists the active key=value pairs.

### What it does
- Loads `assets/config/app.conf` via `rootBundle`
- Parses using `FlatConfig.parse`
- Applies optional `primary-color`, `background-color`, `dark-mode`
- Displays all latest key=value pairs from `config.toMap()`

### Relevant files
- `lib/main.dart` – loads/parses config and renders the UI
- `assets/config/app.conf` – example configuration
- `pubspec.yaml` – adds the local `flatconfig` path dependency and registers the asset

### Run (web)
```bash
cd example/flatconfig_flutter
flutter pub get
flutter run -d chrome
```

Build for static hosting:
```bash
flutter build web
```

### Edit the configuration
Change values in `assets/config/app.conf`, e.g.:
```
title = Flatconfig Flutter Web
welcome-message = "Hello from assets via flatconfig!"
dark-mode = false
primary-color = #6750A4
background-color = #F6F2FF
padding = 20
```

### Notes
- On web, file-based includes and `dart:io` APIs are not available. Use `FlatConfig.parse` on strings (assets or HTTP responses).
- The example depends on the local package via `path: ../../` in `pubspec.yaml`.
