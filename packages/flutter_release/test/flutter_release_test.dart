import 'package:flutter_release/flutter_release.dart';
import 'package:test/test.dart';

void main() {
  test('release', () {
    final release = FlutterBuild(appName: 'test-app', appVersion: 'v0.0.2');
    expect(release.appVersion, 'v0.0.2');
  });
}
