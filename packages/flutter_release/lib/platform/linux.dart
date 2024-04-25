import 'dart:io';

import 'package:flutter_release/build.dart';
import 'package:flutter_release/utils/process.dart';
import 'package:flutter_to_debian/flutter_to_debian.dart';

/// Build the app for Linux.
class LinuxPlatformBuild extends PlatformBuild {
  LinuxPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch = 'x64',
  });

  /// Build the artifact for Windows. It creates a .zip archive.
  @override
  Future<String> build() async {
    return switch (buildType) {
      BuildType.linux => _buildLinux(),
      BuildType.debian => _buildDebian(),
      _ => throw UnsupportedError(
          'BuildType $buildType is not available for Linux!'),
    };
  }

  /// Build the artifact for Linux. It creates a .tar.gz archive.
  Future<String> _buildLinux() async {
    if (commonBuild.installDeps) {
      await runProcess('sudo', ['apt-get', 'update'], runInShell: true);

      await runProcess(
        'sudo',
        [
          'apt-get',
          'install',
          '-y',
          'clang',
          'cmake',
          'ninja-build',
          'pkg-config',
          'libgtk-3-dev',
          'liblzma-dev'
        ],
        runInShell: true,
      );
    }

    await commonBuild.flutterBuild(buildCmd: 'linux');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'linux', extension: 'tar.gz');
    await runProcess(
      'tar',
      [
        '-czf',
        artifactPath,
        '-C',
        'build/linux/$arch/release/bundle',
        '.', // Cannot use asterisk with `-C` option, as it's evaluated by shell
      ],
    );

    return artifactPath;
  }

  /// Build the artifact for Debian. It creates a .deb installer.
  Future<String> _buildDebian() async {
    await _buildLinux();

    final pathToFile = await FlutterToDebian.runBuild(
        version: commonBuild.buildVersion, arch: arch);

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'linux', extension: 'deb');
    final file = File(pathToFile);
    await file.rename(artifactPath);
    return artifactPath;
  }
}
