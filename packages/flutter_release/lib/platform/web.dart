import 'dart:io';

import 'package:dart_release/dart_release.dart';
import 'package:dart_release/utils.dart';
import 'package:flutter_release/build.dart';
import 'package:flutter_release/publish.dart';

/// Build the app for Web.
class WebPlatformBuild extends PlatformBuild {
  WebPlatformBuild({
    required super.buildType,
    required super.flutterBuild,
  });

  /// Build the artifact for Web. It creates a .tar.gz archive.
  @override
  Future<String> build() async {
    await flutterBuild.build(buildCmd: 'web');

    final artifactPath =
        flutterBuild.getArtifactPath(platform: 'web', extension: 'tar.gz');
    await runProcess(
      'tar',
      [
        '-czf',
        artifactPath,
        '-C',
        'build',
        'web',
      ],
    );

    return artifactPath;
  }
}

/// Distribute your app on a web server.
class WebServerDistributor extends PublishDistributor {
  final tmpFolder = '/tmp/flutter_release/build';
  final WebServerConnection serverConnection;
  final String webServerPath;

  WebServerDistributor({
    required super.flutterPublish,
    required super.platformBuild,
    required this.serverConnection,
    required this.webServerPath,
  }) : super(distributorType: PublishDistributorType.webServer);

  @override
  Future<void> publish() async {
    print('Build application...');
    final outputPath = await platformBuild.build();
    final outputFile = File(outputPath);

    // Create tmp folder
    await runProcess('mkdir', ['-p', tmpFolder]);

    try {
      // Ensure files are at the correct path.
      await runProcess(
        'tar',
        [
          '-xzf',
          outputFile.absolute.path,
          '-C',
          tmpFolder,
        ],
      );

      await serverConnection.upload(
        sourcePath: tmpFolder,
        webServerPath: webServerPath,
        isDryRun: flutterPublish.isDryRun,
      );
    } catch (_) {
      rethrow;
    } finally {
      // Remove tmp folder
      await runProcess('rm', ['-r', tmpFolder]);
      await serverConnection.dispose();
    }
  }
}
