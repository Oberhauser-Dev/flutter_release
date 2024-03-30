import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter_release/flutter_release.dart';

import 'build.dart';

// Publish
const commandPublish = 'publish';
const argPublishStage = 'stage';
const argDryRun = 'dry-run';

// Publish: Google Play
const commandAndroidGooglePlay = 'android-google-play';
const argFastlaneSecretsJsonBase64 = 'fastlane-secrets-json-base64';

class PublishCommand extends Command {
  @override
  final name = commandPublish;
  @override
  final description = 'Publish the app with the specified distributor.';

  PublishCommand() {
    addSubcommand(PublishAndroidGooglePlayCommand());
  }
}

abstract class CommonPublishCommand extends Command {
  CommonPublishCommand() {
    addBuildArgs(argParser);
    argParser.addOption(argPublishStage);
    argParser.addFlag(argDryRun);
  }

  PublishDistributor getPublishDistributor(
      ArgResults results, CommonPublish commonPublish);

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');

    final stageStr = results[argPublishStage] as String?;
    final isDryRun = results[argDryRun] as bool?;

    final commonPublish = CommonPublish(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildNumber: int.tryParse(results[argBuildNumber] ?? ''),
      buildVersion: results[argBuildVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      isDryRun: isDryRun,
      stage: stageStr == null ? null : PublishStage.values.byName(stageStr),
    );

    final publishDistributor = getPublishDistributor(results, commonPublish);
    await publishDistributor.publish();
    if (isDryRun ?? false) {
      stdout.writeln(
          'Dry run for ${publishDistributor.distributorType.name} was successful!');
    } else {
      stdout.writeln(
          'Publishing to ${publishDistributor.distributorType.name} was successful!');
    }
  }
}

class PublishAndroidGooglePlayCommand extends CommonPublishCommand {
  @override
  final name = commandAndroidGooglePlay;
  @override
  final description = 'Publish the app on Google Play.';

  PublishAndroidGooglePlayCommand() {
    AndroidBuildCommand.addAndroidBuildArgs(argParser);
    argParser.addOption(argFastlaneSecretsJsonBase64);
  }

  @override
  PublishDistributor getPublishDistributor(
    ArgResults results,
    CommonPublish commonPublish,
  ) {
    final platformBuild = AndroidPlatformBuild(
      buildType: BuildType.aab,
      commonBuild: commonPublish,
      keyStoreFileBase64: results[argKeyStoreFileBase64] as String?,
      keyStorePassword: results[argKeyStorePassword] as String?,
      keyAlias: results[argKeyAlias] as String?,
      keyPassword: results[argKeyPassword] as String?,
      arch: results[argArchitecture] as String?,
    );

    return AndroidGooglePlayDistributor(
      commonPublish: commonPublish,
      platformBuild: platformBuild,
      fastlaneSecretsJsonBase64:
          results[argFastlaneSecretsJsonBase64] as String,
    );
  }
}
