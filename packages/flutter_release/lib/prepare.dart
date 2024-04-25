import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter_release/platform/ios.dart';
import 'package:flutter_release/publish.dart';
import 'package:flutter_release/utils/cmd_input.dart';
import 'package:flutter_release/utils/process.dart';

class IosSigningPrepare {
  static final _iosDirectory = 'ios';
  static final _fastlaneDirectory = '$_iosDirectory/fastlane';

  IosSigningPrepare();

  Future<void> prepare() async {
    await brewInstallFastlane();

    if (!(await File('$_fastlaneDirectory/Appfile').exists())) {
      throw 'Please execute `cd ios && fastlane release` once.';
    }

    final iosDir = Directory(_iosDirectory);
    final entities = await iosDir.list().toList();

    // Handle APIs private key file
    FileSystemEntity? apiPrivateKeyFile = entities.singleWhereOrNull((file) {
      final fileName = file.uri.pathSegments.last;
      return fileName.startsWith('AuthKey_') && fileName.endsWith('.p8');
    });

    if (apiPrivateKeyFile == null) {
      throw 'Please generate an App Store connect API Team key and copy it into the `ios` folder, see https://appstoreconnect.apple.com/access/integrations/api .';
    }

    final apiPrivateKeyFileName = apiPrivateKeyFile.uri.pathSegments.last;
    final apiKeyId = apiPrivateKeyFileName.substring(
        'AuthKey_'.length, apiPrivateKeyFileName.indexOf('.p8'));
    print('The API Key id is (api-key-id):\n$apiKeyId\n');

    print('Enter the issuer id of the API key (api-issuer-id):');
    final apiIssuerId = readInput();

    print('Is the team enterprise y/n (team-enterprise, default:"n"):');
    final teamEnterpriseStr = readInput();
    var isTeamEnterprise = false;
    if (teamEnterpriseStr.toLowerCase().startsWith('y')) {
      isTeamEnterprise = true;
    }

    final apiPrivateKeyBase64 =
        base64Encode(await File.fromUri(apiPrivateKeyFile.uri).readAsBytes());

    final apiKeyJsonPath = await generateApiKeyJson(
      apiPrivateKeyBase64: apiPrivateKeyBase64,
      apiKeyId: apiKeyId,
      apiIssuerId: apiIssuerId,
      isTeamEnterprise: isTeamEnterprise,
      workingDirectory: _iosDirectory,
    );

    Future<void> handleCertificate({required bool isDevelopment}) async {
      FileSystemEntity? privateKeyFile = entities.firstWhereOrNull(
          (file) => file.uri.pathSegments.last.endsWith('.p12'));
      FileSystemEntity? certFile = entities.firstWhereOrNull(
          (file) => file.uri.pathSegments.last.endsWith('.cer'));
      if (privateKeyFile == null || certFile == null) {
        // Download and install a new certificate
        await runProcess(
          'fastlane',
          [
            'cert', // get_certificates
            'development:${isDevelopment ? 'true' : 'false'}',
            'force:true',
            '--api_key_path',
            apiKeyJsonPath,
          ],
          workingDirectory: _iosDirectory,
        );

        final entities = await iosDir.list().toList();
        privateKeyFile = entities
            .firstWhere((file) => file.uri.pathSegments.last.endsWith('.p12'));
        certFile = entities
            .firstWhere((file) => file.uri.pathSegments.last.endsWith('.cer'));
      }

      final p12PrivateKeyBase64 =
          base64Encode(await File.fromUri(privateKeyFile.uri).readAsBytes());
      print(
          'Base64 Private Key for ${isDevelopment ? 'Development' : 'Distribution'} (${isDevelopment ? 'development' : 'distribution'}-private-key-base64):\n');
      print('$p12PrivateKeyBase64\n');

      final certBase64 =
          base64Encode(await File.fromUri(certFile.uri).readAsBytes());
      print(
          'Base64 Certificate for ${isDevelopment ? 'Development' : 'Distribution'} (${isDevelopment ? 'development' : 'distribution'}-cert-base64):\n');
      print('$certBase64\n');
    }

    print(
        'Base64 Private Key for App Store connect API (api-private-key-base64):\n');
    print('$apiPrivateKeyBase64\n');

    await handleCertificate(isDevelopment: false);
  }
}
