import 'dart:convert';
import 'dart:io';

import 'package:flutter_release/build.dart';
import 'package:flutter_release/publish.dart';
import 'package:flutter_release/utils/process.dart';

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
    await runProcess(
      'tar',
      [
        '-czf',
        artifactPath,
        '-C',
        'build',
        'web',
      ],
    );

    return artifactPath;
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
