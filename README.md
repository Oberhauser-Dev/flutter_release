# flutter_release

A tool for building, releasing and deploying Flutter apps.

## Example

```
dart pub global run flutter_release \
 --app-name example \
 --app-version v0.0.4 \
 --release-type apk \
 --build-arg=--dart-define=API_URL="https://example.com" \
 --build-arg=--dart-define=API_KEY=12345678
```

## Options:

- `app-name`: The name of the app executable
- `app-version`: Semantic version of the release (like `v1.2.3`), see https://semver.org/
- `build-version`: Specify the build number
- `release-type`: Release one of the following options: `apk`, `web`, `ipk`, `macos`, `windows`, `debian`
- `build-arg`: Add options such as `--dart-define` to the flutter build command
