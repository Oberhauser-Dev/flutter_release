import 'dart:io';

import 'package:flutter_release/build.dart';
import 'package:flutter_release/utils/process.dart';

/// Build the app for MacOS.
class MacOsPlatformBuild extends PlatformBuild {
  MacOsPlatformBuild({
    required super.buildType,
    required super.commonBuild,
    super.arch = 'x64',
  });

  /// Build the artifact for macOS. It creates a .zip archive.
  @override
  Future<String> build() async {
    await commonBuild.flutterBuild(buildCmd: 'macos');

    // The App's build file/folder name (*.app) is not equal to [appName], so must read the actual file name.
    // Must be read out after build!
    final appNameFile = File('./macos/Flutter/ephemeral/.app_filename');
    final dotAppName = (await appNameFile.readAsString()).trim();

    final artifactPath =
        commonBuild.getArtifactPath(platform: 'macos', extension: 'zip');
    await runProcess(
      'ditto',
      [
        '-c',
        '-k',
        '--sequesterRsrc',
        '--keepParent',
        'build/macos/Build/Products/Release/$dotAppName',
        artifactPath,
      ],
    );

    return artifactPath;
  }
}
