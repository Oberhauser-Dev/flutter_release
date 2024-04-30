import 'dart:convert';
import 'dart:io';

import 'package:dart_release/build.dart';
import 'package:dart_release/utils/process.dart';

class DartDeploy {
  final bool isDryRun;

  DartDeploy({
    bool? isDryRun,
  }) : isDryRun = isDryRun ?? false;
}

abstract class Deployment {
  final DartDeploy dartDeploy;
  final DartBuild dartBuild;

  Deployment({
    required this.dartDeploy,
    required this.dartBuild,
  });

  Future<void> deploy();
}

class WebDeployment extends Deployment {
  final WebServerConnection serverConnection;
  final String webServerPath;
  final String? preScriptPath;
  final String? postScriptPath;

  WebDeployment({
    required super.dartDeploy,
    required super.dartBuild,
    required this.serverConnection,
    required this.webServerPath,
    this.preScriptPath,
    this.postScriptPath,
  });

  final tmpFolder = '/tmp/dart_release/build';

  @override
  Future<void> deploy() async {
    print('Build application...');
    final outputPath = await dartBuild.bundle();
    final outputFile = File(outputPath);

    // Create tmp folder
    final appTmpFolder = '$tmpFolder/${dartBuild.appName}';
    await runProcess('mkdir', ['-p', appTmpFolder]);

    // Extract files to the correct path.
    await runProcess(
      'tar',
      [
        '-xzf',
        outputFile.absolute.path,
        '-C',
        appTmpFolder,
      ],
      printCall: true,
    );

    String sanitizedServerPath = webServerPath;
    if (sanitizedServerPath.endsWith('/')) {
      sanitizedServerPath =
          sanitizedServerPath.substring(0, sanitizedServerPath.length - 1);
    }

    if (preScriptPath != null) {
      final preScriptServerPath = '$sanitizedServerPath/pre-run.sh';
      await serverConnection.upload(
        sourcePath: preScriptPath!,
        webServerPath: preScriptServerPath,
        isDryRun: dartDeploy.isDryRun,
      );
      await serverConnection.run('bash $preScriptServerPath');
    }

    await serverConnection.upload(
      sourcePath: '$appTmpFolder/',
      webServerPath: '$sanitizedServerPath/',
      isDryRun: dartDeploy.isDryRun,
    );

    if (postScriptPath != null) {
      final postScriptServerPath = '$sanitizedServerPath/post-run.sh';
      await serverConnection.upload(
        sourcePath: postScriptPath!,
        webServerPath: postScriptServerPath,
        isDryRun: dartDeploy.isDryRun,
      );
      await serverConnection.run('bash $postScriptServerPath');
    }

    if (dartDeploy.isDryRun) {
      print('Did NOT deploy: Remove `--dry-run` flag for deploying.');
    } else {
      print('Deploying...');
    }

    // Remove tmp folder
    await runProcess('rm', ['-r', tmpFolder]);
  }
}

class WebServerConnection {
  final String host;
  final int port;
  final String sshUser;
  final String? sshPrivateKeyBase64;
  final String? sshPrivateKeyPassphrase;
  List<String> sshArgs = [];

  WebServerConnection({
    required this.host,
    int? port,
    required this.sshUser,
    this.sshPrivateKeyBase64,
    this.sshPrivateKeyPassphrase,
  }) : port = port ?? 22;

  /// Initialize SSH config.
  Future<void> _init() async {
    if (sshArgs.isNotEmpty) return;

    sshArgs = [
      '-p',
      port.toString(),
      '-o',
      'StrictHostKeyChecking=accept-new',
      '-o',
      'IdentitiesOnly=yes',
    ];

    // User may already have a private key.
    if (sshPrivateKeyBase64 == null) {
      return;
    }

    final sshConfigFolder = '${Platform.environment['HOME']}/.ssh';
    await Directory(sshConfigFolder).create(recursive: true);

    // Write keys to be able to login to server
    final sshPrivateKeyFile = File('$sshConfigFolder/id_ed25519_dart_release');
    await sshPrivateKeyFile.writeAsBytes(base64.decode(sshPrivateKeyBase64!));

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
        File('$sshConfigFolder/id_ed25519_dart_release.pub');
    await sshPublicKeyFile.writeAsString(result.stdout);

    // Set permissions right for public ssh key
    await runProcess(
      'chmod',
      [
        '644',
        sshPublicKeyFile.path,
      ],
    );

    sshArgs.addAll([
      '-i',
      sshPrivateKeyFile.path,
    ]);
  }

  Future<void> run(String cmd) async {
    await _init();
    await runProcess('ssh', ['$sshUser@$host', ...sshArgs, cmd]);
  }

  Future<void> upload({
    bool isDryRun = false,
    required String sourcePath,
    required String webServerPath,
  }) async {
    await _init();

    if (webServerPath.endsWith('/')) {
      await run(
          '[ -d $webServerPath ] || (echo Directory $webServerPath not found >&2 && false)');
    }

    final rsyncArgs = [
      '-az',
      '-e',
      'ssh ${sshArgs.join(' ')}',
      sourcePath,
      // Must have a trailing slash, if want the contents of a folder
      '$sshUser@$host:$webServerPath',
    ];
    if (isDryRun) rsyncArgs.add('--dry-run');
    await runProcess(
      'rsync',
      rsyncArgs,
    );
  }
}
