import 'dart:io';

import 'package:flutter_to_debian/flutter_to_debian.dart';

/// Class which holds the necessary attributes to perform a release on various
/// platforms for the specified [buildType].
class BuildManager {
  String appName;
  BuildType buildType;
  String appVersion;
  String buildVersion;
  int buildNumber;
  List<String> buildArgs;
  String releaseFolder;
  bool installDeps = true;
  String? arch;

  BuildManager({
    required this.appName,
    required this.buildType,
    String? appVersion,
    String? buildVersion,
    int? buildNumber,
    this.buildArgs = const [],
    this.installDeps = true,
    String? arch,
    String? releaseFolder,
  })  : appVersion = appVersion ?? 'v0.0.1',
        buildVersion =
            buildVersion ?? (appVersion ?? 'v0.0.1').replaceFirst('v', ''),
        buildNumber = buildNumber ?? 0,
        arch = arch ??
            ((buildType == BuildType.windows ||
                    buildType == BuildType.linux ||
                    buildType == BuildType.debian ||
                    buildType == BuildType.macos)
                ? 'x64'
                : null),
        releaseFolder = releaseFolder ?? 'build/releases';

  /// Release the app for the given platform release type.
  /// Returns the absolute output path.
  Future<String> build() async {
    await Directory(releaseFolder).create(recursive: true);
    switch (buildType) {
      case BuildType.apk:
        return await _buildAndroidApk();
      case BuildType.aab:
        return await _buildAndroidAab();
      case BuildType.ipa:
        return await _buildIOS();
      case BuildType.web:
        return await _buildWeb();
      case BuildType.windows:
        return await _buildWindows();
      case BuildType.linux:
        return await _buildLinux();
      case BuildType.debian:
        return await _buildDebian();
      case BuildType.macos:
        return await _buildMacOs();
    }
  }

  /// Build the flutter binaries for the platform given in [buildCmd].
  Future<void> _build({required String buildCmd}) async {
    final arguments = [
      'build',
      buildCmd,
      '--build-name',
      buildVersion,
      '--build-number',
      buildNumber.toString(),
      ...buildArgs,
    ];
    print('flutter ${arguments.join(' ')}');
    final ProcessResult result = await Process.run(
      'flutter',
      arguments,
      runInShell: true,
    );

    if (result.exitCode == 0) {
      return;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  /// Build the artifact for Android. It creates a .apk installer.
  Future<String> _buildAndroidApk() async {
    await _build(buildCmd: 'apk');

    final artifactPath =
        _getArtifactPath(platform: 'android', extension: 'apk');
    final file = File('build/app/outputs/flutter-apk/app-release.apk');
    await file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for Android. It creates a .aab installer.
  Future<String> _buildAndroidAab() async {
    await _build(buildCmd: 'appbundle');

    final artifactPath =
        _getArtifactPath(platform: 'android', extension: 'aab');
    final file = File('build/app/outputs/bundle/release/app-release.aab');
    await file.rename(artifactPath);
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
        [
          'apt-get',
          'update',
        ],
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
    await file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for macOS. It creates a .zip archive.
  Future<String> _buildMacOs() async {
    await _build(buildCmd: 'macos');

    // The App's build file/folder name (*.app) is not equal to [appName], so must read the actual file name.
    // Must be read out after build!
    final appNameFile = File('./macos/Flutter/ephemeral/.app_filename');
    final dotAppName = (await appNameFile.readAsString()).trim();

    final artifactPath = _getArtifactPath(platform: 'macos', extension: 'zip');
    final ProcessResult result = await Process.run(
      'ditto',
      [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        'build/macos/Build/Products/Release/$dotAppName',
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

/// Enumerates the types of builds.
enum BuildType {
  /// Build APK for Android.
  apk,

  /// Build app bundle for Android.
  aab,

  /// Build for Web.
  web,

  /// Build for iOS.
  ipa,

  /// Build binary for macOS.
  macos,

  /// Build binary for Windows.
  windows,

  /// Build binary for Linux.
  linux,

  /// Build deb for Debian.
  debian,
}
