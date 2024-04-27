import 'package:flutter_release/flutter_release.dart';

class FlutterPublish {
  final bool isDryRun;
  final PublishStage? stage;

  FlutterPublish({
    this.stage,
    bool? isDryRun,
  }) : isDryRun = isDryRun ?? false;
}

/// Enumerates the types of publishing platforms.
enum PublishDistributorType {
  /// Publish in the Google Play Store.
  androidGooglePlay,

  /// Publish on a Web Server.
  webServer,

  /// Publish in the iOS App Store.
  iosAppStore,

  /// Publish in the macOS App Store.
  macAppStore,

  /// Publish in Microsoft Store.
  windowsMsStore,

  /// Publish as Ubuntu Package.
  linuxUbuntu,

  /// Publish as Ubuntu Package.
  linuxSnap,
}

/// A distributor, where you can publish your app, such as an app store.
abstract class PublishDistributor {
  final PublishDistributorType distributorType;

  final PlatformBuild platformBuild;

  final FlutterPublish flutterPublish;

  PublishDistributor({
    required this.distributorType,
    required this.platformBuild,
    required this.flutterPublish,
  }) {
    // Must be a release for publishing
    platformBuild.flutterBuild.buildArgs.add('--release');
  }

  Future<void> publish();
}

/// The [stage] of publishing.
enum PublishStage {
  /// Publish the app to the public.
  production,

  /// Publish a ready stage of your app.
  beta,

  /// Publish an early stage of your app.
  alpha,

  /// Publish only visible to internal testers.
  internal,
}
