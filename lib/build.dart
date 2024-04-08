import 'dart:convert';
import 'dart:io';

import 'package:flutter_to_debian/flutter_to_debian.dart';

/// Class which holds the necessary attributes to perform a build on various
/// platforms for the specified [buildType].
class CommonBuild {
  final String appName;
  final String appVersion;
  String buildVersion;
  int buildNumber;
  List<String> buildArgs;
  final String releaseFolder;
  final bool installDeps;

  CommonBuild({
    required this.appName,
    String? appVersion,
    String? buildVersion,
    int? buildNumber,
    this.buildArgs = const [],
    this.installDeps = true,
    String? releaseFolder,
  })  : appVersion = appVersion ?? 'v0.0.1',
        buildVersion =
            buildVersion ?? (appVersion ?? 'v0.0.1').replaceFirst('v', ''),
        buildNumber = buildNumber ?? 0,
        releaseFolder = releaseFolder ?? 'build/releases';

  /// Build the flutter binaries for the platform given in [buildCmd].
  Future<void> flutterBuild({required String buildCmd}) async {
    await Directory(releaseFolder).create(recursive: true);
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
      // Must run in shell to correctly resolve paths on Windows
      runInShell: true,
    );

    if (result.exitCode != 0) throw Exception(result.stderr.toString());
  }

  /// Get the output path, where the artifact should be placed.
  String getArtifactPath(
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
  ios,

  /// Build app store bundle for iOS.
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

/// The platform where you want your app to be build for.
abstract class PlatformBuild {
  final String? arch;
  final BuildType buildType;
  final CommonBuild commonBuild;

  PlatformBuild(
      {this.arch, required this.buildType, required this.commonBuild});

  /// Release the app for the given platform release type.
  /// Returns the absolute output path.
  Future<String> build();
}

/// Build the app for Android.
class AndroidPlatformBuild extends PlatformBuild {
  static final _androidDirectory = 'android';
  static final _keyStoreFile = 'keystore.jks';

  final String? keyStoreFileBase64;
  final String? keyStorePassword;
  final String? keyAlias;
  final String? keyPassword;

  AndroidPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch,
    this.keyStoreFileBase64,
    this.keyStorePassword,
    this.keyAlias,
    String? keyPassword,
  }) : keyPassword = keyPassword ?? keyStorePassword;

  /// Build the artifact for Android. It creates a .apk installer.
  Future<String> _buildAndroidApk() async {
    await commonBuild.flutterBuild(buildCmd: 'apk');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'android', extension: 'apk');
    final file = File('build/app/outputs/flutter-apk/app-release.apk');
    await file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for Android. It creates a .aab installer.
  Future<String> _buildAndroidAab() async {
    await commonBuild.flutterBuild(buildCmd: 'appbundle');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'android', extension: 'aab');
    final file = File('build/app/outputs/bundle/release/app-release.aab');
    await file.rename(artifactPath);
    return artifactPath;
  }

  @override
  Future<String> build() async {
    if (keyStoreFileBase64 != null &&
        keyStorePassword != null &&
        keyAlias != null &&
        keyPassword != null) {
      // Check if key signing is prepared
      final buildGradleFile = File('$_androidDirectory/app/build.gradle');
      final buildGradleFileContents = await buildGradleFile.readAsString();
      if (!(buildGradleFileContents.contains('key.properties') &&
          buildGradleFileContents.contains('keyAlias') &&
          buildGradleFileContents.contains('keyPassword') &&
          buildGradleFileContents.contains('storeFile') &&
          buildGradleFileContents.contains('storePassword'))) {
        throw Exception(
          'Signing is not configured for Android, please follow the instructions:\n'
          'https://docs.flutter.dev/deployment/android#configure-signing-in-gradle',
        );
      }

      // Save keystore file
      final keyStoreFile = File('$_androidDirectory/$_keyStoreFile');
      await keyStoreFile.writeAsBytes(base64.decode(keyStoreFileBase64!));

      final signingKeys = '''
storePassword=$keyStorePassword
keyPassword=$keyPassword
keyAlias=$keyAlias
storeFile=${keyStoreFile.absolute.path}
    ''';
      await File('$_androidDirectory/key.properties')
          .writeAsString(signingKeys);
    }

    return switch (buildType) {
      BuildType.aab => _buildAndroidAab(),
      BuildType.apk => _buildAndroidApk(),
      _ => throw UnsupportedError(
          'BuildType $buildType is not available for Android!'),
    };
  }
}

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
    if (result.exitCode != 0) throw Exception(result.stderr.toString());

    return artifactPath;
  }
}

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
      ProcessResult result = await Process.run(
        'sudo',
        [
          'apt-get',
          'update',
        ],
        runInShell: true,
      );
      if (result.exitCode != 0) throw Exception(result.stderr.toString());

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

      if (result.exitCode != 0) throw Exception(result.stderr.toString());
    }

    await commonBuild.flutterBuild(buildCmd: 'linux');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'linux', extension: 'tar.gz');
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

    if (result.exitCode != 0) throw Exception(result.stderr.toString());

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

/// Build the app for MacOS.
class MacOsPlatformBuild extends PlatformBuild {
  MacOsPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch = 'x64',
  });

  /// Build the artifact for macOS. It creates a .zip archive.
  @override
  Future<String> build() async {
    await commonBuild.flutterBuild(buildCmd: 'macos');

    // The App's build file/folder name (*.app) is not equal to [appName], so must read the actual file name.
    // Must be read out after build!
    final appNameFile = File('./macos/Flutter/ephemeral/.app_filename');
    final dotAppName = (await appNameFile.readAsString()).trim();

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'macos', extension: 'zip');
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

    if (result.exitCode != 0) throw Exception(result.stderr.toString());

    return artifactPath;
  }
}

/// Build the app for iOS.
class IosPlatformBuild extends PlatformBuild {
  IosPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch,
  });

  /// Build the artifact for iOS App Store. It creates a .ipa bundle.
  Future<String> _buildIosApp() async {
    // TODO: build signed app, independently from publish.
    await commonBuild.flutterBuild(buildCmd: 'ios');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'ios', extension: 'zip');
    final ProcessResult result = await Process.run(
      'ditto',
      [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        'build/ios/iphoneos/Runner.app',
        artifactPath,
      ],
    );

    if (result.exitCode != 0) throw Exception(result.stderr.toString());

    return artifactPath;
  }

  /// Build the artifact for iOS App Store. It creates a .ipa bundle.
  Future<String> _buildIosIpa() async {
    // Ipa build will fail resolving the provisioning profile, this is done later by fastlane.
    await commonBuild.flutterBuild(buildCmd: 'ipa');

    // Does not create ipa at this point
    // final artifactPath =
    //     commonBuild.getArtifactPath(platform: 'ios', extension: 'ipa');
    // final file = File('build/app/outputs/flutter-apk/app-release.apk');
    // await file.rename(artifactPath);
    return '';
  }

  /// Build the artifact for iOS. Not supported as it requires signing.
  @override
  Future<String> build() async {
    return switch (buildType) {
      BuildType.ios => _buildIosApp(),
      BuildType.ipa => _buildIosIpa(),
      _ => throw UnsupportedError(
          'BuildType $buildType is not available for iOS!'),
    };
  }
}

/// Build the app for Web.
class WebPlatformBuild extends PlatformBuild {
  WebPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch,
  });

  /// Build the artifact for Web. It creates a .tar.gz archive.
  @override
  Future<String> build() async {
    await commonBuild.flutterBuild(buildCmd: 'web');

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'web', extension: 'tar.gz');
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

    if (result.exitCode != 0) throw Exception(result.stderr.toString());

    return artifactPath;
  }
}
