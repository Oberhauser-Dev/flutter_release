import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:flutter_release/flutter_release.dart';

// Common
const argAppName = 'app-name';
const argAppVersion = 'app-version';
const argBuildNumber = 'build-number';
const argBuildVersion = 'build-version';
const argBuildArg = 'build-arg';
const argReleaseFolder = 'release-folder';
const argArchitecture = 'arch'; //x64, arm64

// Build
const commandBuild = 'build';

// Build Android
const argKeyStoreFileBase64 = 'keystore-file-base64';
const argKeyStorePassword = 'keystore-password';
const argKeyAlias = 'key-alias';
const argKeyPassword = 'key-password';

class BuildCommand extends Command {
  @override
  final name = commandBuild;
  @override
  final description = 'Build the app in the specified format.';

  BuildCommand() {
    addSubcommand(AndroidApkBuildCommand());
    addSubcommand(AndroidAppbundleBuildCommand());
    addSubcommand(IosIpaBuildCommand());
    addSubcommand(IosAppBuildCommand());
    addSubcommand(WindowsBuildCommand());
    addSubcommand(LinuxBuildCommand());
    addSubcommand(DebianBuildCommand());
    addSubcommand(WebBuildCommand());
    addSubcommand(MacOsBuildCommand());
  }
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

abstract class CommonBuildCommand extends Command {
  CommonBuildCommand() {
    addBuildArgs(argParser);
    argParser.addOption(argReleaseFolder);
  }

  @override
  String get name => buildType.name;

  BuildType get buildType;

  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild);

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');
    final commonBuild = CommonBuild(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildNumber: int.tryParse(results[argBuildNumber] ?? ''),
      buildVersion: results[argBuildVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      releaseFolder: results[argReleaseFolder] as String?,
    );
    final platformBuild = getPlatformBuild(results, commonBuild);
    stdout.writeln(await platformBuild.build());
  }
}

abstract class AndroidBuildCommand extends CommonBuildCommand {
  static void addAndroidBuildArgs(ArgParser argParser) {
    argParser
      ..addOption(argKeyStoreFileBase64)
      ..addOption(argKeyStorePassword)
      ..addOption(argKeyAlias)
      ..addOption(argKeyPassword);
  }

  AndroidBuildCommand() {
    addAndroidBuildArgs(argParser);
  }

  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return AndroidPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      keyStoreFileBase64: results[argKeyStoreFileBase64] as String?,
      keyStorePassword: results[argKeyStorePassword] as String?,
      keyAlias: results[argKeyAlias] as String?,
      keyPassword: results[argKeyPassword] as String?,
      arch: results[argArchitecture] as String?,
    );
  }
}

class AndroidApkBuildCommand extends AndroidBuildCommand {
  @override
  final description = 'Build the app as Android apk.';

  @override
  BuildType buildType = BuildType.apk;
}

class AndroidAppbundleBuildCommand extends AndroidBuildCommand {
  @override
  final description = 'Build the app as Android app bundle.';

  @override
  BuildType buildType = BuildType.aab;
}

class WindowsBuildCommand extends CommonBuildCommand {
  @override
  final description = 'Build the app as Windows desktop executable.';

  @override
  BuildType buildType = BuildType.windows;

  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return WindowsPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      arch: (results[argArchitecture] as String?) ?? 'x64',
    );
  }
}

class LinuxBuildCommand extends CommonBuildCommand {
  @override
  final description = 'Build the app as Linux desktop executable.';

  @override
  BuildType buildType = BuildType.linux;

  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return LinuxPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      arch: (results[argArchitecture] as String?) ?? 'x64',
    );
  }
}

class DebianBuildCommand extends LinuxBuildCommand {
  @override
  String get description => 'Build the app as Debian desktop executable.';

  @override
  BuildType get buildType => BuildType.debian;
}

class WebBuildCommand extends CommonBuildCommand {
  @override
  final description = 'Build the app as Web bundle.';

  @override
  BuildType buildType = BuildType.web;

  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return WebPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      arch: results[argArchitecture] as String?,
    );
  }
}

class MacOsBuildCommand extends CommonBuildCommand {
  @override
  final description = 'Build the app as MacOS .app wrapped in a zip archive.';

  @override
  BuildType buildType = BuildType.macos;

  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return MacOsPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      arch: (results[argArchitecture] as String?) ?? 'x64',
    );
  }
}

abstract class IosBuildCommand extends CommonBuildCommand {
  @override
  PlatformBuild getPlatformBuild(ArgResults results, CommonBuild commonBuild) {
    return IosPlatformBuild(
      buildType: buildType,
      commonBuild: commonBuild,
      arch: results[argArchitecture] as String?,
    );
  }
}

class IosIpaBuildCommand extends IosBuildCommand {
  @override
  final description = 'Build the app as iOS .ipa.';

  @override
  BuildType buildType = BuildType.ipa;
}

class IosAppBuildCommand extends IosBuildCommand {
  @override
  final description = 'Build the app as iOS .app.';

  @override
  BuildType buildType = BuildType.ios;
}
