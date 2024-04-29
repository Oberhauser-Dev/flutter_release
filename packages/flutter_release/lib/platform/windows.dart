import 'package:dart_release/utils.dart';
import 'package:flutter_release/flutter_release.dart';

/// Build the app for Windows.
class WindowsPlatformBuild extends PlatformBuild {
  WindowsPlatformBuild({
    required super.buildType,
    required super.flutterBuild,
  });

  /// Build the artifact for Windows. It creates a .zip archive.
  @override
  Future<String> build() async {
    await flutterBuild.build(buildCmd: 'windows');
    final cpuArchitecture = getCpuArchitecture();
    final flutterArch = getFlutterCpuArchitecture(cpuArchitecture);
    final artifactPath = flutterBuild.getArtifactPath(
      platform: 'windows',
      arch: cpuArchitecture,
      extension: 'zip',
    );
    await runProcess(
      'powershell',
      [
        'Compress-Archive',
        '-Force',
        '-Path',
        'build\\windows\\$flutterArch\\runner\\Release\\*',
        '-DestinationPath',
        artifactPath.replaceAll('/', '\\'),
      ],
    );

    return artifactPath;
  }
}
