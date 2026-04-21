# Luxe Budget Desktop

Luxe Budget Desktop is a premium orange-and-black expense tracker built with Flutter for macOS and Windows.

## What Is Ready

- Premium desktop UI with transaction management and category management
- Local JSON persistence
- CSV export
- Monthly breakdown, category share, and spending-over-time analytics
- GitHub Actions workflow for Windows release builds

## Local Run

From this folder:

```bash
../flutter/bin/flutter pub get
../flutter/bin/flutter run -d macos
```

## GitHub Setup

This folder is meant to be its own repository root.

Suggested flow:

1. Create a new empty GitHub repository named something like `luxe-budget-desktop`.
2. Push this folder as the repository root.
3. Open the repository on GitHub.
4. Go to `Actions`.
5. Run `Build Windows App`.

## Windows `.exe` Build

The workflow file is:

`.github/workflows/build-windows.yml`

When that workflow finishes, GitHub uploads an artifact named `luxe-budget-windows`.

Inside that ZIP is the Windows release build, including the `.exe` and the runtime files that must stay beside it.

Important:

- Do not send only the `.exe` by itself.
- Unzip the artifact and keep the full folder contents together.
- Your friends should run the `.exe` from inside that unzipped folder.

## Suggested Repo Contents

These files are the key pieces to keep in GitHub:

- `lib/main.dart`
- `pubspec.yaml`
- `windows/`
- `macos/`
- `.github/workflows/build-windows.yml`

## macOS Package

The native Swift macOS app and DMG packaging live in the parent workspace outside this Flutter folder.
