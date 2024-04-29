import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_release/dart_release.dart';

import 'build.dart';

// Deploy
const commandDeploy = 'deploy';
const argDryRun = 'dry-run';
const argWebServerHost = 'host';
const argWebServerPath = 'path';
const argWebServerPort = 'ssh-port';
const argWebSshUser = 'ssh-user';
const argWebSshPrivateKeyBase64 = 'ssh-private-key-base64';
const argWebSshPrivateKeyPassphrase = 'ssh-private-key-passphrase';
const argWebPreScript = 'pre-script';
const argWebPostScript = 'post-script';

class DeployCommand extends Command {
  @override
  final name = commandDeploy;
  @override
  final description = 'Deploy the app with the specified distributor.';

  DeployCommand() {
    addBuildArgs(argParser);
    argParser.addFlag(argDryRun);
    argParser.addOption(argWebServerHost);
    argParser.addOption(argWebServerPort);
    argParser.addOption(argWebSshUser);
    argParser.addOption(argWebSshPrivateKeyBase64);
    argParser.addOption(argWebSshPrivateKeyPassphrase);
    argParser.addOption(argWebServerPath);
    argParser.addOption(argWebPreScript);
    argParser.addOption(argWebPostScript);
  }

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');

    final isDryRun = results[argDryRun] as bool?;

    final dartDeploy = DartDeploy(
      isDryRun: isDryRun,
    );

    final dartBuild = DartBuild(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      mainPath: results[argMainPath] as String,
      includedPaths: results[argIncludePath] as List<String>,
    );

    final deploy = getDeploy(
        results: results, dartDeploy: dartDeploy, dartBuild: dartBuild);
    await deploy.deploy();
    if (isDryRun ?? false) {
      stdout.writeln('Dry run for ${deploy.runtimeType} was successful!');
    } else {
      stdout.writeln('Deploying to ${deploy.runtimeType} was successful!');
    }
  }

  Deployment getDeploy({
    required ArgResults results,
    required DartDeploy dartDeploy,
    required DartBuild dartBuild,
  }) {
    return WebDeployment(
      dartDeploy: dartDeploy,
      dartBuild: dartBuild,
      webServerPath: results[argWebServerPath] as String,
      serverConnection: WebServerConnection(
        host: results[argWebServerHost] as String,
        port: int.tryParse(results[argWebServerPort] ?? ''),
        sshUser: results[argWebSshUser] as String,
        sshPrivateKeyBase64: results[argWebSshPrivateKeyBase64] as String?,
        // sshPrivateKeyPassphrase: results[argWebSshPrivateKeyPassphrase] as String?,
      ),
    );
  }
}
