# Repository Guidelines

## Project Structure & Module Organization

Slate is a Flutter app for macOS and Android. Application code lives in `lib/`:

- `lib/models/` contains Freezed data models and JSON serialization.
- `lib/repositories/` wraps Supabase CRUD and realtime behavior.
- `lib/providers/` contains Riverpod providers and notifiers.
- `lib/screens/` and `lib/widgets/` contain UI surfaces and reusable components.
- `lib/utils/` holds shared date and calendar helpers.

Platform projects are in `android/` and `macos/`. App assets are in `assets/`, currently under `assets/icon/`. Tests live in `test/`.

## Build, Test, and Development Commands

- `flutter pub get` installs Dart and Flutter dependencies.
- `flutter run -d macos` runs the primary local development target.
- `flutter test` runs widget and unit tests in `test/`.
- `flutter analyze` runs the analyzer with `flutter_lints`.
- `dart run build_runner build --delete-conflicting-outputs` regenerates Riverpod, Freezed, and JSON code after changing `@riverpod`, `@freezed`, or `json_serializable` types.
- `flutter build apk --release` builds Android release output.
- `flutter build macos --release` builds the macOS release app.

Generated `*.g.dart` and `*.freezed.dart` files are present locally but should be regenerated after source model/provider changes.

## Coding Style & Naming Conventions

Use Dart defaults: two-space indentation, trailing commas for multiline Flutter widget trees, and `dart format` before committing. Follow `flutter_lints` from `analysis_options.yaml`.

Name Dart files in `snake_case.dart`. Use `PascalCase` for classes and widgets, `camelCase` for variables, methods, providers, and repository members. Keep feature code aligned with the existing flow:

`Freezed model -> Repository -> @riverpod Notifier -> Screen/Widget`

## Testing Guidelines

Use `flutter_test` for widget tests and standard Dart tests for pure logic. Place tests under `test/` and name files `*_test.dart`. Prefer tests around providers, repositories, recurrence/date logic, and UI states that can regress. Run `flutter test` and `flutter analyze` before opening a PR.

## Commit & Pull Request Guidelines

Recent commits use short, imperative summaries such as `Notes: soft delete with trash/restore` and `Fix calendar task cards to left-align at 60% width`. Keep the first line specific and under roughly 72 characters when possible.

Pull requests should include a concise description, test results, linked issues if applicable, and screenshots or screen recordings for UI changes on macOS/Android.

## Security & Configuration Tips

Do not commit Supabase secrets. `lib/env/env.dart` is local-only and should define `supabaseUrl` and `supabaseAnonKey`. App code should not set `user_id` on inserts; database defaults and RLS derive it from the authenticated user.
