export 'android.dart';
export 'ios.dart';
export 'linux.dart';
export 'macos.dart';
export 'web.dart';
export 'windows.dart';

String getFlutterCpuArchitecture(String arch) {
  return switch (arch) {
    'amd64' => 'x64',
    'arm64' => 'arm64',
    _ => throw UnimplementedError(
        'Cpu architecture $arch is not supported by Flutter. '
        'See https://github.com/flutter/flutter/issues/75823 for more information.',
      ),
  };
}
