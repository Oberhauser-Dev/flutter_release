import 'dart:convert';
import 'dart:io';

import 'package:flutter_release/flutter_release.dart';

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
    ProcessResult result = await Process.run(
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

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    result = await Process.run(
      'sudo',
      [
        'gem',
        'install',
        'fastlane',
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

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
    result = await Process.run(
      'fastlane',
      [
        'run',
        'validate_play_store_json_key',
        // 'json_key:${fastlaneSecretsJsonFile.absolute.path}',
      ],
      workingDirectory: _androidDirectory,
      runInShell: true,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    final track = switch (commonPublish.stage) {
      PublishStage.production => 'production',
      PublishStage.beta => 'beta',
      PublishStage.alpha => 'alpha',
      _ => 'internal',
    };

    Future<int?> getLastVersionCode() async {
      result = await Process.run(
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

      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
      }

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

//     final fastlaneFastfile = '''
// update_fastlane
//
// default_platform(:android)
//
// platform :android do
//   desc "Submit a new Alpha Build to internal track"
//   lane :alpha do
//     upload_to_play_store(track: 'internal', release_status: 'draft')
//     slack(message: 'Successfully distributed a new beta build')
//   end
//
//   desc "Submit a new Beta Build to Crashlytics Beta"
//   lane :beta do
//     upload_to_play_store(track: 'beta')
//     slack(message: 'Successfully distributed a new beta build')
//   end
//
//   desc "Deploy a new version to the Google Play"
//   lane :deploy do
//     upload_to_play_store
//     slack(message: 'Successfully distributed a new deploy build')
//   end
// end
//     ''';
//     await File('$_fastlaneDirectory/Fastfile').writeAsString(fastlaneFastfile);

    // Init fastlane / get metadata
    // result = await Process.run(
    //   'fastlane',
    //   [
    //     'supply',
    //     'init',
    //   ],
    //   workingDirectory: _androidDirectory,
    //   runInShell: true,
    // );
    //
    // if (result.exitCode != 0) {
    //   throw Exception(result.stderr.toString());
    // }

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
      final arguments = [
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
      ];
      print('fastlane ${arguments.join(' ')}');
      result = await Process.run(
        'fastlane',
        arguments,
        workingDirectory: _androidDirectory,
        runInShell: true,
      );

      if (result.exitCode != 0) {
        throw Exception(result.stderr.toString());
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
    ProcessResult result = await Process.run('mkdir', ['-p', tmpFolder]);
    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    // Ensure files are at the correct path.
    result = await Process.run(
      'tar',
      [
        '-xzf',
        outputFile.absolute.path,
        '-C',
        tmpFolder,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    final sshConfigFolder = '${Platform.environment['HOME']}/.ssh';
    await Directory(sshConfigFolder).create(recursive: true);

    // Write keys to be able to login to server
    final sshPrivateKeyFile =
        File('$sshConfigFolder/id_ed25519_flutter_release');
    await sshPrivateKeyFile.writeAsBytes(base64.decode(sshPrivateKeyBase64));

    // Set permissions right for private ssh key
    result = await Process.run(
      'chmod',
      [
        '600',
        sshPrivateKeyFile.path,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

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
    result = await Process.run(
      'ssh-keygen',
      generatePublicKeyArgs,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    final sshPublicKeyFile =
        File('$sshConfigFolder/id_ed25519_flutter_release.pub');
    await sshPublicKeyFile.writeAsString(result.stdout);

    // Set permissions right for public ssh key
    result = await Process.run(
      'chmod',
      [
        '644',
        sshPublicKeyFile.path,
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

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
    result = await Process.run(
      'ssh',
      [
        '$sshUser@$host',
        ...sshArgs,
        '[ -d $sanitizedServerPath ] || (echo Directory $sanitizedServerPath not found >&2 && false)',
      ],
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

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
    result = await Process.run(
      'rsync',
      rsyncArgs,
    );

    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }

    // Remove tmp folder
    result = await Process.run('rm', ['-r', tmpFolder]);
    if (result.exitCode != 0) {
      throw Exception(result.stderr.toString());
    }
  }
}
