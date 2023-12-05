import 'dart:io';

import 'package:flutter_to_debian/flutter_to_debian.dart';

/// Class which holds the necessary attributes to perform a release on various
/// platforms for the specified [releaseType].
class FlutterRelease {
  String appName;
  ReleaseType releaseType;
  String appVersion;
  String buildVersion;
  int buildNumber;
  List<String> buildArgs;
  String releaseFolder = 'build/releases';
  bool installDeps = true;
  String arch;

  FlutterRelease({
    required this.appName,
    required this.releaseType,
    this.appVersion = 'v0.0.1',
    String? buildVersion,
    this.buildNumber = 0,
    this.buildArgs = const [],
    this.installDeps = true,
    String? arch,
  })  : buildVersion = buildVersion ?? appVersion.replaceFirst('v', ''),
        arch = arch ??
            ((releaseType == ReleaseType.windows ||
                    releaseType == ReleaseType.linux)
                ? 'x64'
                : '');

  /// Release the app for the given platform release type.
  Future<String> release() async {
    await Directory(releaseFolder).create(recursive: true);
    switch (releaseType) {
      case ReleaseType.apk:
        return await _buildAndroid();
      case ReleaseType.ipa:
        return await _buildIOS();
      case ReleaseType.web:
        return await _buildWeb();
      case ReleaseType.windows:
        return await _buildWindows();
      case ReleaseType.linux:
        return await _buildLinux();
      case ReleaseType.debian:
        return await _buildDebian();
      case ReleaseType.macos:
        return await _buildMacOs();
    }
  }

  /// Build the flutter binaries for the platform given in [buildCmd].
  Future<void> _build({required String buildCmd}) async {
    final ProcessResult result = await Process.run(
      'flutter',
      [
        'build',
        buildCmd,
        '--build-name',
        buildVersion,
        '--build-number',
        buildNumber.toString(),
        ...buildArgs,
      ],
      runInShell: true,
    );

    if (result.exitCode == 0) {
      return;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Build the artifact for Android. It creates a .apk installer.
  Future<String> _buildAndroid() async {
    await _build(buildCmd: 'apk');

    final artifactPath =
        _getArtifactPath(platform: 'android', extension: 'apk');
    final file = File('build/app/outputs/flutter-apk/app-release.apk');
    file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for iOS. Not supported as it requires signing.
  Future<String> _buildIOS() async {
    throw Exception('Releasing ipa is not supported!');
  }

  /// Build the artifact for Linux. It creates a .tar.gz archive.
  Future<String> _buildLinux() async {
    if (installDeps) {
      ProcessResult result = await Process.run(
        'sudo',
        ['apt-get', 'update'],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
      }

      result = await Process.run(
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

      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
      }
    }

    await _build(buildCmd: 'linux');

    final artifactPath =
        _getArtifactPath(platform: 'linux', extension: 'tar.gz');
    final ProcessResult result = await Process.run(
      'tar',
      [
        '-czf',
        artifactPath,
        '-C',
        'build/linux/$arch/release/bundle',
        '.', // Cannot use asterisk with `-C` option, as it's evaluated by shell
      ],
    );

    if (result.exitCode == 0) {
      return artifactPath;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Build the artifact for Debian. It creates a .deb installer.
  Future<String> _buildDebian() async {
    await _buildLinux();

    final pathToFile =
        await FlutterToDebian.runBuild(version: buildVersion, arch: arch);

    final artifactPath = _getArtifactPath(platform: 'linux', extension: 'deb');
    final file = File(pathToFile);
    file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for macOS. It creates a .zip archive.
  Future<String> _buildMacOs() async {
    await _build(buildCmd: 'macos');

    final artifactPath = _getArtifactPath(platform: 'macos', extension: 'zip');
    final ProcessResult result = await Process.run(
      'ditto',
      [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        'build/macos/Build/Products/Release/$appName.app',
        artifactPath,
      ],
    );

    if (result.exitCode == 0) {
      return artifactPath;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Build the artifact for Windows. It creates a .zip archive.
  Future<String> _buildWindows() async {
    await _build(buildCmd: 'windows');

    final artifactPath =
        _getArtifactPath(platform: 'windows', extension: 'zip');
    final ProcessResult result = await Process.run(
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
    if (result.exitCode == 0) {
      return artifactPath;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Build the artifact for Web. It creates a .tar.gz archive.
  Future<String> _buildWeb() async {
    await _build(buildCmd: 'web');

    final artifactPath = _getArtifactPath(platform: 'web', extension: 'tar.gz');
    final ProcessResult result = await Process.run(
      'tar',
      [
        '-czf',
        artifactPath,
        '-C',
        'build',
        'web',
      ],
    );

    if (result.exitCode == 0) {
      return artifactPath;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Get the output path, where the artifact should be placed.
  String _getArtifactPath(
      {required String platform, required String extension}) {
    return '$releaseFolder/$appName-$platform-$appVersion.$extension';
  }
}

/// Enumerates the types of release.
enum ReleaseType {
  /// Release for Android.
  apk,

  /// Release for Web.
  web,

  /// Release for iOS.
  ipa,

  /// Binary for macOS.
  macos,

  /// Binary for Windows.
  windows,

  /// Binary for Linux.
  linux,

  /// Binary for Linux.
  debian,
}
