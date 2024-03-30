import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:flutter_release/cli/build.dart';
import 'package:flutter_release/cli/publish.dart';

void main(List<String> arguments) async {
  exitCode = 0;
  final commandRunner = CommandRunner('flutter_release',
      'A command line tool to build, release and publish Flutter applications.');

  commandRunner.addCommand(BuildCommand());
  commandRunner.addCommand(PublishCommand());
  await commandRunner.run(arguments);
}
