import 'package:flutter_release/build.dart';
import 'package:flutter_release/utils/process.dart';

/// Build the app for Windows.
class WindowsPlatformBuild extends PlatformBuild {
  WindowsPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch = 'x64',
  });

  /// Build the artifact for Windows. It creates a .zip archive.
  @override
  Future<String> build() async {
    await commonBuild.flutterBuild(buildCmd: 'windows');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'windows', extension: 'zip');
    await runProcess(
      'powershell',
      [
        'Compress-Archive',
        '-Force',
        '-Path',
        'build\\windows\\$arch\\runner\\Release\\*',
        '-DestinationPath',
        artifactPath.replaceAll('/', '\\'),
      ],
    );

    return artifactPath;
  }
}
