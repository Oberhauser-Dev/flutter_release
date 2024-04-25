import 'dart:convert';
import 'dart:io';

import 'package:flutter_release/flutter_release.dart';
import 'package:flutter_release/platform/ios.dart';
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
  final String apiKeyId;
  final String apiIssuerId;
  final String apiPrivateKeyBase64;
  final String contentProviderId;
  final String teamId;
  final bool isTeamEnterprise;
  final String distributionPrivateKeyBase64;

  /// This may can be removed once getting certificates is implemented in fastlane
  /// https://developer.apple.com/documentation/appstoreconnectapi/list_and_download_certificates
  final String distributionCertificateBase64;

  IosAppStoreDistributor({
    required super.commonPublish,
    required super.platformBuild,
    required this.appleUsername,
    required this.apiKeyId,
    required this.apiIssuerId,
    required this.apiPrivateKeyBase64,
    required this.contentProviderId,
    required this.teamId,
    bool? isTeamEnterprise,
    required this.distributionPrivateKeyBase64,
    required this.distributionCertificateBase64,
  })  : isTeamEnterprise = isTeamEnterprise ?? false,
        super(distributorType: PublishDistributorType.iosAppStore);

  @override
  Future<void> publish() async {
    print('Install dependencies...');

    final isProduction = commonPublish.stage == PublishStage.production;

    await brewInstallFastlane();

    // Create tmp keychain to be able to run non interactively,
    // see https://github.com/fastlane/fastlane/blob/df12128496a9a0ad349f8cf8efe6f9288612f2cb/fastlane/lib/fastlane/actions/setup_ci.rb#L37
    final fastlaneKeychainName = 'fastlane_tmp_keychain';
    await runProcess(
      'fastlane',
      [
        'run',
        'setup_ci',
      ],
      workingDirectory: _iosDirectory,
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

    final apiKeyJsonPath = await generateApiKeyJson(
      apiPrivateKeyBase64: apiPrivateKeyBase64,
      apiKeyId: apiKeyId,
      apiIssuerId: apiIssuerId,
      isTeamEnterprise: isTeamEnterprise,
      workingDirectory: _iosDirectory,
    );

    Future<void> installCertificates({bool isDevelopment = false}) async {
      final signingIdentity = isDevelopment ? 'Development' : 'Distribution';

      final codeSigningIdentity =
          'iPhone ${isDevelopment ? 'Developer' : 'Distribution'}';
      // Disable automatic code signing
      await runProcess(
        'fastlane',
        [
          'run',
          'update_code_signing_settings',
          'use_automatic_signing:false',
          'path:Runner.xcodeproj',
          'code_sign_identity:$codeSigningIdentity',
          'sdk:iphoneos*',
        ],
        workingDirectory: _iosDirectory,
      );

      final p12PrivateKeyBytes =
          base64Decode(isDevelopment ? '' : distributionPrivateKeyBase64);
      final distributionPrivateKeyFile =
          File('$_iosDirectory/$signingIdentity.p12');
      await distributionPrivateKeyFile.writeAsBytes(p12PrivateKeyBytes);

      // Import private key
      await runProcess(
        'fastlane',
        [
          'run',
          'import_certificate',
          'certificate_path:$signingIdentity.p12',
          'keychain_name:$fastlaneKeychainName',
        ],
        workingDirectory: _iosDirectory,
      );

      final certBytes =
          base64Decode(isDevelopment ? '' : distributionCertificateBase64);
      final certFile = File('$_iosDirectory/$signingIdentity.cer');
      await certFile.writeAsBytes(certBytes);

      // Import certificate
      await runProcess(
        'fastlane',
        [
          'run',
          'import_certificate',
          'certificate_path:$signingIdentity.cer',
          'keychain_name:$fastlaneKeychainName',
        ],
        workingDirectory: _iosDirectory,
      );

      // Download provisioning profile
      await runProcess(
        'fastlane',
        [
          'sigh',
          // get_provisioning_profile
          //'filename:$signingIdentity.mobileprovision', // only works for newly created profiles
          '--api_key_path',
          apiKeyJsonPath,
        ],
        workingDirectory: _iosDirectory,
      );

      final provisioningProfilePath =
          '${isDevelopment ? 'Development' : 'AppStore'}_$bundleId.mobileprovision';

      // Install provisioning profile
      await runProcess(
        'fastlane',
        [
          'run',
          'install_provisioning_profile',
          'path:$provisioningProfilePath',
        ],
        workingDirectory: _iosDirectory,
      );

      // Update provisioning profile
      await runProcess(
        'fastlane',
        [
          'run',
          'update_project_provisioning',
          'xcodeproj:Runner.xcodeproj',
          // 'build_configuration:${isDevelopment ? '/Debug|Profile/gm' : 'Release'}',
          // 'build_configuration:${isDevelopment ? 'Debug' : 'Release'}',
          // 'profile:./$signingIdentity.mobileprovision', // Custom name only working for newly created profiles
          'profile:$provisioningProfilePath',
          'code_signing_identity:$codeSigningIdentity',
        ],
        workingDirectory: _iosDirectory,
      );
    }

    // await installCertificates(isDevelopment: true);
    await installCertificates(isDevelopment: false);

    await runProcess(
      'fastlane',
      [
        'run',
        'update_project_team',
        'path:Runner.xcodeproj',
        'teamid:$teamId',
      ],
      workingDirectory: _iosDirectory,
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
    );

    if (commonPublish.isDryRun) {
      print('Did NOT publish: Remove `--dry-run` flag for publishing.');
    } else {
      print('Publish...');
      if (!isProduction) {
        await runProcess(
          'fastlane',
          // upload_to_testflight
          ['pilot', 'upload', '--api_key_path', apiKeyJsonPath],
          workingDirectory: _iosDirectory,
          printCall: true,
        );
      } else {
        await runProcess(
          'fastlane',
          ['upload_to_app_store', '--api_key_path', apiKeyJsonPath],
          workingDirectory: _iosDirectory,
          printCall: true,
        );
      }
    }
  }
}

Future<void> brewInstallFastlane() async {
  try {
    await runProcess(
      'which',
      ['fastlane'],
    );
  } catch (_) {
    await runProcess(
      'brew',
      ['install', 'fastlane'],
    );
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
