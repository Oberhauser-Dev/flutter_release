List<String> buildApiKeyArgs({
  required String apiPrivateKeyFilePath,
  required String apiKeyId,
  required String apiIssuerId,
  bool isTeamEnterprise = false,
}) {
  return [
    '--api_key',
    '{"filepath":"$apiPrivateKeyFilePath",'
        '"key_id":"$apiKeyId",'
        '"issuer_id":"$apiIssuerId",'
        '"in_house":$isTeamEnterprise}'
  ];
}
