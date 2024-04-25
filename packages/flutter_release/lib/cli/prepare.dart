import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:flutter_release/flutter_release.dart';

const commandPrepare = 'prepare';

class PrepareCommand extends Command {
  @override
  final name = commandPrepare;
  @override
  final description = 'Prepare the app locally.';

  PrepareCommand() {
    addSubcommand(IosPrepareCommand());
  }
}

class IosPrepareCommand extends Command {
  @override
  String description = 'Prepare the ios app on the local machine.';

  @override
  String name = 'ios';

  IosPrepareCommand();

  @override
  FutureOr? run() async {
    final results = argResults;
    if (results == null) throw ArgumentError('No arguments provided');

    await IosSigningPrepare().prepare();
  }
}
