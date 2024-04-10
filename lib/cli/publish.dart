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

// Publish: iOS App Store
const commandIosAppStore = 'ios-app-store';
const argIosAppleUsername = 'apple-username';
const argIosApiKeyId = 'api-key-id';
const argIosApiIssuerId = 'api-issuer-id';
const argIosApiPrivateKeyBase64 = 'api-private-key-base64';
const argIosContentProviderId = 'content-provider-id';
const argIosTeamId = 'team-id';
const argIosTeamEnterprise = 'team-enterprise';
const argIosDistributionPrivateKeyBase64 = 'distribution-private-key-base64';
const argIosDistributionCertificateBase64 = 'distribution-cert-base64';

// Publish: Web Server
const commandWebServer = 'web-server';
const argWebServerHost = 'host';
const argWebServerPath = 'path';
const argWebServerPort = 'ssh-port';
const argWebSshUser = 'ssh-user';
const argWebSshPrivateKeyBase64 = 'ssh-private-key-base64';
const argWebSshPrivateKeyPassphrase = 'ssh-private-key-passphrase';

class PublishCommand extends Command {
  @override
  final name = commandPublish;
  @override
  final description = 'Publish the app with the specified distributor.';

  PublishCommand() {
    addSubcommand(PublishAndroidGooglePlayCommand());
    addSubcommand(PublishIosAppStoreCommand());
    addSubcommand(PublishWebServerCommand());
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
    argParser.addOption(argFastlaneSecretsJsonBase64, mandatory: true);
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

class PublishIosAppStoreCommand extends CommonPublishCommand {
  @override
  final name = commandIosAppStore;
  @override
  final description = 'Publish the app on iOS App Store.';

  PublishIosAppStoreCommand() {
    argParser
      ..addOption(argIosAppleUsername, mandatory: true, help: 'aka `apple_id`')
      ..addOption(argIosApiKeyId, mandatory: true)
      ..addOption(argIosApiIssuerId, mandatory: true)
      ..addOption(argIosApiPrivateKeyBase64, mandatory: true)
      ..addOption(
        argIosContentProviderId,
        mandatory: true,
        help: 'aka `itc_team_id`, see: '
            'https://appstoreconnect.apple.com/WebObjects/iTunesConnect.woa/ra/user/detail',
      )
      ..addOption(argIosTeamId, mandatory: true, help: 'aka `team_id`')
      ..addFlag(argIosTeamEnterprise, help: 'aka `in_house`')
      ..addOption(argIosDistributionPrivateKeyBase64, mandatory: true)
      ..addOption(argIosDistributionCertificateBase64, mandatory: true);
  }

  @override
  PublishDistributor getPublishDistributor(
    ArgResults results,
    CommonPublish commonPublish,
  ) {
    final platformBuild = IosPlatformBuild(
      buildType: BuildType.ipa,
      commonBuild: commonPublish,
      arch: results[argArchitecture] as String?,
    );

    return IosAppStoreDistributor(
      commonPublish: commonPublish,
      platformBuild: platformBuild,
      appleUsername: results[argIosAppleUsername] as String,
      apiKeyId: results[argIosApiKeyId] as String,
      apiIssuerId: results[argIosApiIssuerId] as String,
      apiPrivateKeyBase64: results[argIosApiPrivateKeyBase64] as String,
      contentProviderId: results[argIosContentProviderId] as String,
      teamId: results[argIosTeamId] as String,
      isTeamEnterprise: results[argIosTeamEnterprise] as bool?,
      distributionPrivateKeyBase64:
          results[argIosDistributionPrivateKeyBase64] as String,
      distributionCertificateBase64:
          results[argIosDistributionCertificateBase64] as String,
    );
  }
}

class PublishWebServerCommand extends CommonPublishCommand {
  @override
  final name = commandWebServer;
  @override
  final description = 'Publish the app on a Web server.';

  PublishWebServerCommand() {
    argParser
      ..addOption(argWebServerHost, mandatory: true)
      ..addOption(argWebServerPort)
      ..addOption(argWebServerPath, mandatory: true)
      ..addOption(argWebSshUser, mandatory: true)
      ..addOption(argWebSshPrivateKeyBase64, mandatory: true);
    // ..addOption(argWebSshPrivateKeyPassphrase); Passphrase currently not supported
  }

  @override
  PublishDistributor getPublishDistributor(
    ArgResults results,
    CommonPublish commonPublish,
  ) {
    final platformBuild = WebPlatformBuild(
      buildType: BuildType.web,
      commonBuild: commonPublish,
    );

    return WebServerDistributor(
      commonPublish: commonPublish,
      platformBuild: platformBuild,
      host: results[argWebServerHost] as String,
      port: int.tryParse(results[argWebServerPort] ?? ''),
      webServerPath: results[argWebServerPath] as String,
      sshUser: results[argWebSshUser] as String,
      sshPrivateKeyBase64: results[argWebSshPrivateKeyBase64] as String,
      // sshPrivateKeyPassphrase: results[argWebSshPrivateKeyPassphrase] as String?,
    );
  }
}
