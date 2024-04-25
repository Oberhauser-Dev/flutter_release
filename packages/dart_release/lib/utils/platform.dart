import 'dart:io';

/// Get current CPU architecture
String getCpuArchitecture() {
  String cpu;
  if (Platform.isWindows) {
    cpu = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'unknown';
  } else {
    var info = Process.runSync('uname', ['-m']);
    cpu = info.stdout.toString().replaceAll('\n', '').trim();
  }
  switch (cpu.toLowerCase()) {
    case 'x86' || 'i386' || '386' || 'i686' || 'x32' || 'amd32':
      cpu = 'amd32';
    case 'x86_64' || 'x64' || 'amd64':
      cpu = 'amd64';
    case 'arm':
      cpu = 'arm32';
    case 'aarch64':
      cpu = 'arm64';
  }
  return cpu;
}
