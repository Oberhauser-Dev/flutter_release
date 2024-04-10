import 'dart:convert';
import 'dart:io';

import 'package:flutter_release/flutter_release.dart';
import 'package:flutter_release/utils/process.dart';

class CommonPublish extends CommonBuild {
  final bool isDryRun;
  final PublishStage? stage;

  CommonPublish({
    required super.appName,
    super.appVersion,
    super.buildVersion,
    super.buildNumber,
    super.buildArgs,
    super.installDeps,
    this.stage,
    bool? isDryRun,
  }) : isDryRun = isDryRun ?? false {
    // Must be a release for publishing
    buildArgs.add('--release');
  }
}

/// Enumerates the types of publishing platforms.
enum PublishDistributorType {
  /// Publish in the Google Play Store.
  androidGooglePlay,

  /// Publish on a Web Server.
  webServer,

  /// Publish in the iOS App Store.
  iosAppStore,

  /// Publish in the macOS App Store.
  macAppStore,

  /// Publish in Microsoft Store.
  windowsMsStore,

  /// Publish as Ubuntu Package.
  linuxUbuntu,

  /// Publish as Ubuntu Package.
  linuxSnap,
}

/// A distributor, where you can publish your app, such as an app store.
abstract class PublishDistributor {
  final PublishDistributorType distributorType;

  final PlatformBuild platformBuild;

  final CommonPublish commonPublish;

  PublishDistributor({
    required this.distributorType,
    required this.platformBuild,
    required this.commonPublish,
  });

  Future<void> publish();
}

/// The [stage] of publishing.
enum PublishStage {
  /// Publish the app to the public.
  production,

  /// Publish a ready stage of your app.
  beta,

  /// Publish an early stage of your app.
  alpha,

  /// Publish only visible to internal testers.
  internal,
}

/// Distribute your app on the Google Play store.
class AndroidGooglePlayDistributor extends PublishDistributor {
  static final _androidDirectory = 'android';
  static final _fastlaneDirectory = '$_androidDirectory/fastlane';
  static final _fastlaneSecretsJsonFile = 'fastlane-secrets.json';

  final String fastlaneSecretsJsonBase64;

  AndroidGooglePlayDistributor({
    required super.commonPublish,
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

    final track = switch (commonPublish.stage) {
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
      platformBuild.commonBuild.buildNumber = versionCode;
    }
    final outputPath = await platformBuild.build();
    final outputFile = File(outputPath);

    if (commonPublish.isDryRun) {
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
          switch (commonPublish.stage) {
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

/// Distribute your app on the iOS App store.
class IosAppStoreDistributor extends PublishDistributor {
  static final _iosDirectory = 'ios';
  static final _fastlaneDirectory = '$_iosDirectory/fastlane';

  final String appleUsername;
  final String applePassword;
  final String contentProviderId;
  final String teamId;

  IosAppStoreDistributor({
    required super.commonPublish,
    required super.platformBuild,
    required this.appleUsername,
    required this.applePassword,
    required this.contentProviderId,
    required this.teamId,
  }) : super(distributorType: PublishDistributorType.iosAppStore);

  @override
  Future<void> publish() async {
    print('Install dependencies...');

    final isProduction = commonPublish.stage == PublishStage.production;

    await runProcess(
      'brew',
      ['install', 'fastlane'],
    );

    // Determine app bundle id
    final iosAppInfoFile =
        File('$_iosDirectory/Runner.xcodeproj/project.pbxproj');
    final iosAppInfoFileContents = await iosAppInfoFile.readAsString();
    final regex = RegExp(r'(?<=PRODUCT_BUNDLE_IDENTIFIER)(.*)(?=;\n)');
    final match = regex.firstMatch(iosAppInfoFileContents);
    if (match == null) throw Exception('Bundle Id not found');
    var bundleId = match.group(0);
    if (bundleId == null) throw Exception('Bundle Id not found');
    bundleId =
        bundleId.replaceFirst('=', '').replaceAll('.RunnerTests', '').trim();
    print('Use app bundle id: $bundleId');

    final fastlaneAppfile = '''
app_identifier("$bundleId")
apple_id("$appleUsername")
itc_team_id("$contentProviderId")
team_id("$teamId")
    ''';
    await Directory(_fastlaneDirectory).create(recursive: true);
    await File('$_fastlaneDirectory/Appfile').writeAsString(fastlaneAppfile);

    final envFastlane = {
      'FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD': applePassword,
    };

    // Download certificate
    await runProcess(
      'fastlane',
      ['run', 'get_certificates'],
      workingDirectory: _iosDirectory,
      environment: envFastlane,
    );

    // Download provisioning profile
    await runProcess(
      'fastlane',
      ['run', 'get_provisioning_profile', 'filename:AppStore.mobileprovision'],
      workingDirectory: _iosDirectory,
      environment: envFastlane,
    );

    // Update provisioning profile
    await runProcess(
      'fastlane',
      [
        'run',
        'update_project_provisioning',
        'xcodeproj:./Runner.xcodeproj',
        'profile:./AppStore.mobileprovision',
      ],
      workingDirectory: _iosDirectory,
      environment: envFastlane,
    );

    print('Build application...');

    if (!isProduction) {
      final buildVersion = platformBuild.commonBuild.buildVersion;
      // Remove semver suffix
      // See: https://github.com/flutter/flutter/issues/27589
      if (buildVersion.contains('+')) {
        platformBuild.commonBuild.buildVersion = buildVersion.split('+')[0];
        print(
          'Build version was truncated from $buildVersion to '
          '${platformBuild.commonBuild.buildVersion} as required by app store',
        );
      }
      if (buildVersion.contains('-')) {
        platformBuild.commonBuild.buildVersion = buildVersion.split('-')[0];
        print(
          'Build version was truncated from $buildVersion to '
          '${platformBuild.commonBuild.buildVersion} as required by app store',
        );
      }
    }

    // Build xcarchive only
    await platformBuild.build();

    // Build signed ipa
    // https://docs.flutter.dev/deployment/cd
    await runProcess(
      'fastlane',
      [
        'run',
        'build_app',
        'skip_build_archive:true',
        'archive_path:../build/ios/archive/Runner.xcarchive',
      ],
      workingDirectory: _iosDirectory,
      environment: envFastlane,
    );

    if (commonPublish.isDryRun) {
      print('Did NOT publish: Remove `--dry-run` flag for publishing.');
    } else {
      print('Publish...');
      if (!isProduction) {
        await runProcess(
          'fastlane',
          ['pilot', 'upload'],
          workingDirectory: _iosDirectory,
          environment: envFastlane,
          printCall: true,
        );
      } else {
        await runProcess(
          'fastlane',
          ['upload_to_app_store'],
          workingDirectory: _iosDirectory,
          environment: envFastlane,
          printCall: true,
        );
      }
    }
  }
}

/// Distribute your app on a web server.
class WebServerDistributor extends PublishDistributor {
  final String webServerPath;
  final String host;
  final int port;
  final String sshUser;
  final String sshPrivateKeyBase64;
  final String? sshPrivateKeyPassphrase;

  static final tmpFolder = '/tmp/flutter_release/build';

  WebServerDistributor({
    required super.commonPublish,
    required super.platformBuild,
    required this.webServerPath,
    required this.host,
    int? port,
    required this.sshUser,
    required this.sshPrivateKeyBase64,
    this.sshPrivateKeyPassphrase,
  })  : port = port ?? 22,
        super(distributorType: PublishDistributorType.webServer);

  @override
  Future<void> publish() async {
    print('Build application...');
    final outputPath = await platformBuild.build();
    final outputFile = File(outputPath);

    // Create tmp folder
    await runProcess('mkdir', ['-p', tmpFolder]);

    // Ensure files are at the correct path.
    await runProcess(
      'tar',
      [
        '-xzf',
        outputFile.absolute.path,
        '-C',
        tmpFolder,
      ],
    );

    final sshConfigFolder = '${Platform.environment['HOME']}/.ssh';
    await Directory(sshConfigFolder).create(recursive: true);

    // Write keys to be able to login to server
    final sshPrivateKeyFile =
        File('$sshConfigFolder/id_ed25519_flutter_release');
    await sshPrivateKeyFile.writeAsBytes(base64.decode(sshPrivateKeyBase64));

    // Set permissions right for private ssh key
    await runProcess(
      'chmod',
      [
        '600',
        sshPrivateKeyFile.path,
      ],
    );

    final generatePublicKeyArgs = [
      '-y',
      '-f',
      sshPrivateKeyFile.path,
    ];
    if (sshPrivateKeyPassphrase != null) {
      generatePublicKeyArgs
        ..add('-P')
        ..add(sshPrivateKeyPassphrase!);
    }
    final result = await runProcess(
      'ssh-keygen',
      generatePublicKeyArgs,
    );

    final sshPublicKeyFile =
        File('$sshConfigFolder/id_ed25519_flutter_release.pub');
    await sshPublicKeyFile.writeAsString(result.stdout);

    // Set permissions right for public ssh key
    await runProcess(
      'chmod',
      [
        '644',
        sshPublicKeyFile.path,
      ],
    );

    String sanitizedServerPath = webServerPath;

    if (!sanitizedServerPath.endsWith('/')) {
      sanitizedServerPath += '/';
    }

    final sshArgs = [
      '-p',
      port.toString(),
      '-o',
      'StrictHostKeyChecking=accept-new',
      '-o',
      'IdentitiesOnly=yes',
      '-i',
      sshPrivateKeyFile.path,
    ];
    await runProcess(
      'ssh',
      [
        '$sshUser@$host',
        ...sshArgs,
        '[ -d $sanitizedServerPath ] || (echo Directory $sanitizedServerPath not found >&2 && false)',
      ],
    );

    if (commonPublish.isDryRun) {
      print('Did NOT publish: Remove `--dry-run` flag for publishing.');
    } else {
      print('Publish...');
    }
    final rsyncArgs = [
      '-az',
      '-e',
      'ssh ${sshArgs.join(' ')}',
      '$tmpFolder/web/', // Must have a trailing slash
      '$sshUser@$host:$sanitizedServerPath',
    ];
    if (commonPublish.isDryRun) rsyncArgs.add('--dry-run');
    await runProcess(
      'rsync',
      rsyncArgs,
    );

    // Remove tmp folder
    await runProcess('rm', ['-r', tmpFolder]);
  }
}
