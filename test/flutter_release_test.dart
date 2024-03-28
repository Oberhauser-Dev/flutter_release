import 'package:flutter_release/flutter_release.dart';
import 'package:test/test.dart';

void main() {
  test('release', () {
    final release = BuildManager(
        appName: 'test-app', buildType: BuildType.apk, appVersion: 'v0.0.2');
    expect(release.appVersion, 'v0.0.2');
  });
}
