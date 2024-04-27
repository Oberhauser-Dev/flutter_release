import 'dart:convert';
import 'dart:io';

import 'package:flutter_release/build.dart';
import 'package:flutter_release/publish.dart';
import 'package:flutter_release/utils/process.dart';

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
    required super.flutterBuild,
    super.arch,
    this.keyStoreFileBase64,
    this.keyStorePassword,
    this.keyAlias,
    String? keyPassword,
  }) : keyPassword = keyPassword ?? keyStorePassword;

  /// Build the artifact for Android. It creates a .apk installer.
  Future<String> _buildAndroidApk() async {
    await flutterBuild.build(buildCmd: 'apk');

    final artifactPath =
        flutterBuild.getArtifactPath(platform: 'android', extension: 'apk');
    final file = File('build/app/outputs/flutter-apk/app-release.apk');
    await file.rename(artifactPath);
    return artifactPath;
  }

  /// Build the artifact for Android. It creates a .aab installer.
  Future<String> _buildAndroidAab() async {
    await flutterBuild.build(buildCmd: 'appbundle');

    final artifactPath =
        flutterBuild.getArtifactPath(platform: 'android', extension: 'aab');
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

/// Distribute your app on the Google Play store.
class AndroidGooglePlayDistributor extends PublishDistributor {
  static final _androidDirectory = 'android';
  static final _fastlaneDirectory = '$_androidDirectory/fastlane';
  static final _fastlaneSecretsJsonFile = 'fastlane-secrets.json';

  final String fastlaneSecretsJsonBase64;

  AndroidGooglePlayDistributor({
    required super.flutterPublish,
    required super.platformBuild,
    required this.fastlaneSecretsJsonBase64,
  }) : super(distributorType: PublishDistributorType.androidGooglePlay);

  @override
  Future<void> publish() async {
    print('Install dependencies...');
    await runProcess(
      'sudo',
      [
        'apt-get',
        'install',
        '-y',
        'ruby',
        'ruby-dev',
      ],
      runInShell: true,
    );

    await runProcess(
      'sudo',
      [
        'gem',
        'install',
        'fastlane',
      ],
      runInShell: true,
    );

    final buildGradleFile = File('$_androidDirectory/app/build.gradle');
    final buildGradleFileContents = await buildGradleFile.readAsString();

    // Save Google play store credentials file
    final fastlaneSecretsJsonFile =
        File('$_androidDirectory/$_fastlaneSecretsJsonFile');
    await fastlaneSecretsJsonFile
        .writeAsBytes(base64.decode(fastlaneSecretsJsonBase64));

    final regex = RegExp(r'(?<=applicationId)(.*)(?=\n)');
    final match = regex.firstMatch(buildGradleFileContents);
    if (match == null) throw Exception('Application Id not found');
    var packageName = match.group(0);
    if (packageName == null) throw Exception('Application Id not found');
    packageName = packageName.trim();
    packageName = packageName.replaceAll('"', '');
    packageName = packageName.replaceAll("'", '');
    final fastlaneAppfile = '''
json_key_file("${fastlaneSecretsJsonFile.absolute.path}")
package_name("$packageName")
    ''';
    await Directory(_fastlaneDirectory).create(recursive: true);
    await File('$_fastlaneDirectory/Appfile').writeAsString(fastlaneAppfile);

    // Check if play store credentials are valid
    await runProcess(
      'fastlane',
      [
        'run',
        'validate_play_store_json_key',
        // 'json_key:${fastlaneSecretsJsonFile.absolute.path}',
      ],
      workingDirectory: _androidDirectory,
      runInShell: true,
    );

    final track = switch (flutterPublish.stage) {
      PublishStage.production => 'production',
      PublishStage.beta => 'beta',
      PublishStage.alpha => 'alpha',
      _ => 'internal',
    };

    Future<int?> getLastVersionCode() async {
      final result = await runProcess(
        'fastlane',
        [
          'run',
          'google_play_track_version_codes',
          // 'package_name: app_identifier',
          'track:$track',
        ],
        environment: {'FASTLANE_DISABLE_COLORS': '1'},
        workingDirectory: _androidDirectory,
      );

      // Get latest version code
      const splitter = LineSplitter();
      final lines = splitter.convert(result.stdout);
      final resultSearchStr = 'Result:';
      final versionCodesStr = lines.last
          .substring(
            lines.last.indexOf(resultSearchStr) + resultSearchStr.length,
          )
          .trim();
      final json = jsonDecode(versionCodesStr);
      return json[0] as int?;
    }

    var versionCode = await getLastVersionCode();
    // Increase versionCode by 1, if available:
    versionCode = versionCode == null ? null : (versionCode + 1);
    print(
      'Use $versionCode as next version code unless build number is overridden.',
    );

    print('Build application...');
    if (versionCode != null) {
      platformBuild.flutterBuild.buildNumber = versionCode;
    }
    final outputPath = await platformBuild.build();
    final outputFile = File(outputPath);

    if (flutterPublish.isDryRun) {
      print('Did NOT publish: Remove `--dry-run` flag for publishing.');
    } else {
      print('Publish...');
      await runProcess(
        'fastlane',
        [
          'supply',
          '--aab',
          outputFile.absolute.path,
          '--track',
          track,
          '--release_status',
          switch (flutterPublish.stage) {
            PublishStage.production => 'completed',
            PublishStage.beta => 'completed',
            PublishStage.alpha => 'completed',
            _ => 'draft',
          },
        ],
        workingDirectory: _androidDirectory,
        printCall: true,
        runInShell: true,
      );
    }
  }
}
