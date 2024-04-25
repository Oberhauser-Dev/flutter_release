import 'package:dart_release/dart_release.dart';
import 'package:test/test.dart';

void main() {
  test('release', () {
    final release =
        DartBuild(appName: 'test-app', appVersion: 'v0.0.2', mainPath: '');
    expect(release.appVersion, 'v0.0.2');
  });
}
