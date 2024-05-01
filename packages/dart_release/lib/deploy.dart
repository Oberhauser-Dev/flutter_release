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

    try {
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
        await serverConnection.run(preScriptServerPath);
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
        await serverConnection.run(postScriptServerPath);
      }

      if (dartDeploy.isDryRun) {
        print('Did NOT deploy: Remove `--dry-run` flag for deploying.');
      } else {
        print('Deploying...');
      }
    } catch (_) {
      rethrow;
    } finally {
      // Remove tmp folder
      await runProcess('rm', ['-r', tmpFolder]);
      await serverConnection.dispose();
    }
  }
}

/// Create a SSH connection to a web server.
class WebServerConnection {
  final String host;
  final int port;
  final String sshUser;
  final String? sshPrivateKeyBase64;
  final String? sshPrivateKeyPassphrase;

  final sshConfigFolder = '${Platform.environment['HOME']}/.ssh';

  String get ctlFolder => '$sshConfigFolder/ctl';

  /// The control params using a unified ssh control master
  List<String> sshControlArgs = [];

  WebServerConnection({
    required this.host,
    int? port,
    required this.sshUser,
    this.sshPrivateKeyBase64,
    this.sshPrivateKeyPassphrase,
  }) : port = port ?? 22;

  /// Initialize SSH config.
  Future<void> _init() async {
    if (sshControlArgs.isNotEmpty) return;

    await Directory(ctlFolder).create(recursive: true);
    sshControlArgs = [
      '-o',
      'ControlPath=$ctlFolder/%L-%r@%h:%p',
      '-p',
      port.toString(),
      // sshUser@host cannot be added as rsync handles this on its own.
    ];

    final sshArgs = [
      '-o',
      'StrictHostKeyChecking=accept-new',
      // Run in the background, but wait for connection to be established
      '-nNf',
      '-o',
      'ControlMaster=yes',
      '$sshUser@$host',
      ...sshControlArgs,
    ];

    // User may already have a private key.
    if (sshPrivateKeyBase64 != null) {
      // Write keys to be able to login to server
      final sshPrivateKeyFile =
          File('$sshConfigFolder/id_ed25519_dart_release');
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
        '-o',
        'IdentitiesOnly=yes',
        '-o',
        'IdentityFile=${sshPrivateKeyFile.path}',
      ]);
    }

    await runProcess('ssh', sshArgs);
  }

  Future<void> dispose() async {
    await runProcess('ssh', [
      '-O',
      'exit',
      '$sshUser@$host',
      ...sshControlArgs,
    ]);
    sshControlArgs.clear();
  }

  Future<void> run(String cmd) async {
    await _init();
    await runProcess('ssh', ['$sshUser@$host', ...sshControlArgs, cmd]);
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
      'ssh ${sshControlArgs.join(' ')}',
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
