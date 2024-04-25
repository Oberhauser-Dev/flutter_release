import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:dart_release/dart_release.dart';

// Common
const argAppName = 'app-name';
const argAppVersion = 'app-version';
const argBuildArg = 'build-arg';
const argMainPath = 'main-path';
const argIncludePath = 'include-path';

// Build
const commandBuild = 'build';

class BuildCommand extends Command {
  @override
  final name = commandBuild;
  @override
  final description = 'Build the app in the specified format.';

  BuildCommand() {
    addBuildArgs(argParser);
  }

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');
    final dartBuild = DartBuild(
      appName: results[argAppName] as String,
      appVersion: results[argAppVersion] as String?,
      buildArgs: results[argBuildArg] as List<String>,
      mainPath: results[argMainPath] as String,
      includedPaths: results[argIncludePath] as List<String>,
    );
    stdout.writeln(await dartBuild.bundle());
  }
}

void addBuildArgs(ArgParser parser) {
  parser
    ..addOption(argAppName, abbr: 'n', mandatory: true)
    ..addOption(argAppVersion, abbr: 'v')
    ..addOption(argMainPath, abbr: 'm', mandatory: true)
    ..addMultiOption(argIncludePath, abbr: 'i')
    ..addMultiOption(argBuildArg, abbr: 'o');
}
