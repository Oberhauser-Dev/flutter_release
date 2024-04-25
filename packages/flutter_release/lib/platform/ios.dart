import 'dart:io';

Future<String> generateApiKeyJson({
  required String apiPrivateKeyBase64,
  required String apiKeyId,
  required String apiIssuerId,
  bool isTeamEnterprise = false,
  required String workingDirectory,
}) async {
  final apiKeyJsonContent = '''
{
  "key_id": "$apiKeyId",
  "issuer_id": "$apiIssuerId",
  "key": "$apiPrivateKeyBase64",
  "in_house": $isTeamEnterprise,
  "duration": 1200,
  "is_key_content_base64": true
}
  ''';
  final apiKeyJsonFile = File('$workingDirectory/ApiAuth.json');
  await apiKeyJsonFile.writeAsString(apiKeyJsonContent);

  return apiKeyJsonFile.absolute.path;
}
