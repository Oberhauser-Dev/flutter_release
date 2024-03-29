import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter_release/flutter_release.dart';

// Build
const commandBuild = 'build';
const argAppName = 'app-name';
const argAppVersion = 'app-version';
const argBuildNumber = 'build-number';
const argBuildVersion = 'build-version';
const argBuildArg = 'build-arg';
const argBuildType = 'build-type';
const argReleaseFolder = 'release-folder';
const argArchitecture = 'arch'; //x64, arm64

// Publish
const commandPublish = 'publish';
const argPublishStage = 'stage';
const argDryRun = 'dry-run';

// Publish: Google Play
const commandAndroidGooglePlay = 'android-google-play';
const argFastlaneSecretsJsonBase64 = 'fastlane-secrets-json-base64';
const argKeyStoreFileBase64 = 'keystore-file-base64';
const argKeyStorePassword = 'keystore-password';
const argKeyAlias = 'key-alias';
const argKeyPassword = 'key-password';

void main(List<String> arguments) async {
  exitCode = 0;
  final commandRunner = CommandRunner('flutter_release',
      'A command line tool to build, release and publish Flutter applications.');

  commandRunner.addCommand(BuildCommand());
  commandRunner.addCommand(PublishCommand());
  await commandRunner.run(arguments);
}

void addBuildArgs(ArgParser parser) {
  parser
    ..addOption(argAppName, abbr: 'n', mandatory: true)
    ..addOption(argAppVersion, abbr: 'v')
    ..addOption(argBuildNumber, abbr: 'b')
    ..addOption(argBuildVersion)
    ..addMultiOption(argBuildArg, abbr: 'o')
    ..addOption(argArchitecture);
}

void addPublishArgs(ArgParser parser) {
  parser.addOption(argPublishStage);
  parser.addFlag(argDryRun);
}

class BuildCommand extends Command {
  @override
  final name = commandBuild;
  @override
  final description = 'Build the app in the specified format.';

  BuildCommand() {
    addBuildArgs(argParser);
    argParser
      ..addOption(argBuildType, abbr: 't', mandatory: true)
      ..addOption(argReleaseFolder);
  }

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');
    final buildManager = BuildManager(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildNumber: int.tryParse(results[argBuildNumber] ?? ''),
      buildVersion: results[argBuildVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      buildType: BuildType.values
          .byName((results[argBuildType] as String).toLowerCase()),
      arch: results[argArchitecture] as String?,
      releaseFolder: results[argReleaseFolder] as String?,
    );
    stdout.writeln(await buildManager.build());
  }
}

class PublishCommand extends Command {
  @override
  final name = commandPublish;
  @override
  final description = 'Publish the app with the specified distributor.';

  PublishCommand() {
    addSubcommand(PublishAndroidGooglePlayCommand());
  }
}

class PublishAndroidGooglePlayCommand extends Command {
  @override
  final name = commandAndroidGooglePlay;
  @override
  final description = 'Publish the app on Google Play.';

  PublishAndroidGooglePlayCommand() {
    addBuildArgs(argParser);
    addPublishArgs(argParser);
    argParser
      ..addOption(argFastlaneSecretsJsonBase64)
      ..addOption(argKeyStoreFileBase64)
      ..addOption(argKeyStorePassword)
      ..addOption(argKeyAlias)
      ..addOption(argKeyPassword);
  }

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');
    final stageStr = results[argPublishStage] as String?;
    final isDryRun = results[argDryRun] as bool?;
    final PublishDistributor publishDistributor = AndroidGooglePlayDistributor(
      stage: stageStr == null ? null : PublishStage.values.byName(stageStr),
      fastlaneSecretsJsonBase64:
          results[argFastlaneSecretsJsonBase64] as String,
      keyStoreFileBase64: results[argKeyStoreFileBase64] as String,
      keyStorePassword: results[argKeyStorePassword] as String,
      keyAlias: results[argKeyAlias] as String,
      keyPassword: results[argKeyPassword] as String?,
      isDryRun: isDryRun,
    );

    final publishManager = PublishManager(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildNumber: int.tryParse(results[argBuildNumber] ?? ''),
      buildVersion: results[argBuildVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      publishDistributor: publishDistributor,
      arch: results[argArchitecture] as String?,
      distributor: publishDistributor,
    );
    await publishManager.publish();
    if (isDryRun ?? false) {
      stdout.writeln(
          'Dry run for ${publishDistributor.distributorType.name} was successful!');
    } else {
      stdout.writeln(
          'Publishing to ${publishDistributor.distributorType.name} was successful!');
    }
  }
}
