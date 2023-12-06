import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter_release/flutter_release.dart';

const appName = 'app-name';
const appVersion = 'app-version';
const buildNumber = 'build-number';
const buildArg = 'build-arg';
const releaseType = 'release-type';
const architecture = 'arch'; //x64, arm64

void main(List<String> arguments) async {
  exitCode = 0;
  final parser = ArgParser()
    ..addOption(appName, abbr: 'n')
    ..addOption(appVersion, abbr: 'v')
    ..addOption(buildNumber, abbr: 'b')
    ..addOption(releaseType, abbr: 't')
    ..addMultiOption(buildArg, abbr: 'o')
    ..addOption(architecture);

  ArgResults argResults = parser.parse(arguments);
  // final paths = argResults.rest;

  final release = FlutterRelease(
    appName: argResults[appName] as String,
    appVersion: (argResults[appVersion] ?? 'v0.0.1') as String,
    buildNumber: (argResults[buildNumber] ?? 0) as int,
    buildArgs: argResults[buildArg] as List<String>,
    releaseType: ReleaseType.values
        .byName((argResults[releaseType] as String).toLowerCase()),
    arch: argResults[architecture] as String?
  );

  stdout.writeln(await release.release());
}
