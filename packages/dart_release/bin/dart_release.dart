import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:dart_release/cli/build.dart';
import 'package:dart_release/cli/deploy.dart';

void main(List<String> arguments) async {
  exitCode = 0;
  final commandRunner = CommandRunner('dart_release',
      'A command line tool to build, release and deploy Dart applications.');

  commandRunner.addCommand(BuildCommand());
  commandRunner.addCommand(DeployCommand());
  await commandRunner.run(arguments);
}
