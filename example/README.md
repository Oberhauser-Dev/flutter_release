# flutter_release example

```shell
dart pub global run flutter_release \
 --app-name example \
 --app-version v0.0.4-alpha.3 \
 --build-number 123 \
 --release-type apk \
 --build-arg=--dart-define=API_URL="https://example.com" \
 --build-arg=--dart-define=API_KEY=12345678
```
