import 'dart:io';

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

  FlutterRelease({
    required this.appName,
    required this.releaseType,
    this.appVersion = 'v0.0.1',
    String? buildVersion,
    this.buildNumber = 0,
    this.buildArgs = const [],
    this.installDeps = true,
  }) : buildVersion = buildVersion ?? appVersion.replaceFirst('v', '');

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

  Future<String> _buildAndroid() async {
    await _build(buildCmd: 'apk');

    final artifactPath =
        _getArtifactPath(platform: 'android', extension: 'apk');
    final file = File('build/app/outputs/flutter-apk/app-release.apk');
    file.rename(artifactPath);
    return artifactPath;
  }

  Future<String> _buildIOS() async {
    throw Exception('Releasing ipa is not supported!');
  }

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
        'build/linux/x64/release/bundle',
        '.', // Cannot use asterisk with `-C` option, as it's evaluated by shell
      ],
    );

    if (result.exitCode == 0) {
      return artifactPath;
    } else {
      throw Exception(result.stderr.toString());
    }
  }

  Future<String> _buildDebian() async {
    await _buildLinux();

    // Activate flutter_to_debian
    ProcessResult result = await Process.run(
      'dart',
      [
        'pub',
        'global',
        'activate',
        'https://github.com/gustl22/flutter_to_debian.git',
        '--source=git',
        '--git-ref=v2',
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    result = await Process.run(
      'dart',
      [
        'pub',
        'global',
        'run',
        'flutter_to_debian',
        'build',
        '--build-version',
        buildVersion,
      ],
      runInShell: true,
    );

    final debianAppName = appName.replaceAll('_', '-');

    final artifactPath = _getArtifactPath(platform: 'linux', extension: 'deb');
    final file = File(
        'build/linux/x64/release/debian/${debianAppName}_${buildVersion}_amd64.deb');
    file.rename(artifactPath);
    return artifactPath;
  }

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
        'build\\windows\\runner\\Release\\*',
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

  String _getArtifactPath(
      {required String platform, required String extension}) {
    return '$releaseFolder/$appName-$platform-$appVersion.$extension';
  }
}

/// Release type:
/// [apk] -> Android
/// [web] -> Web
/// [ipa] -> iOS
/// [macos] -> macOS
/// [windows] -> Windows
/// [linux] -> Linux
/// [debian] -> Linux
enum ReleaseType {
  apk,
  web,
  ipa,
  macos,
  windows,
  linux,
  debian,
}
