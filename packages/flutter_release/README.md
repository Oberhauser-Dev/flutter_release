# flutter_release

A tool for building and publishing Flutter apps, e.g. on GitHub, the Google Play Store and Apple's App Store.
See also the according [GitHub action](https://github.com/marketplace/actions/flutter-release-action).

## Example

Build:

```shell
flutter_release build apk \
 --app-name example \
 --app-version v0.0.1-alpha.1 \
 --build-arg=--dart-define=API_URL=https://example.com \
 --build-arg=--dart-define=API_KEY=12345678
```

Publish:

```shell
flutter_release publish android-google-play \
 --dry-run \
 --stage internal \
 --app-name wrestling_scoreboard_client \
 --app-version v0.0.1-alpha.1 \
 --build-arg=--dart-define=API_URL=https://example.com \
 --build-arg=--dart-define=API_KEY=12345678 \
 --fastlane-secrets-json-base64=$(base64 --wrap=0 android/fastlane-secrets.json) \
 --keystore-file-base64=$(base64 --wrap=0 android/keystore.jks) \
 --keystore-password=<mykeystorepassword> \
 --key-alias=<mykeyalias>
```

If the command is not found (in the PATH), try: `dart pub global run flutter_release ...`.

Note that you have to pass the base64 arguments without any newline characters:

```shell
MY_BASE_64=$(base64 --wrap=0 /myfile)
```

Or remove them afterward:

```shell
MY_BASE_64="${MY_BASE_64//$'\n'/}"
```

## Options:

- `app-name`: The name of the app executable
- `app-version`: Semantic version of the release (like `v1.2.3`), see https://semver.org/
- `build-number`: Specify the build number (also used as version code for Android, but is handled automatically)
- `build-type`: Release one of the following options: `apk`, `web`, `ipk`, `macos`, `windows`, `debian`
- `build-arg`: Add options such as `--dart-define` to the flutter build command

## Supported Features

| Platform    | Android |               | iOS             | web          | Windows           | macOS           | Linux   |          |
|-------------|---------|---------------|-----------------|--------------|-------------------|-----------------|---------|----------|
| **Build**   | apk ✓   | aab ✓         | ipa ❌           | web ✓        | windows ✓         | macos ✓         | linux ✓ | debian ✓ |
| **Publish** |         | Google Play ✓ | iOS App Store ✓ | Web Server ✓ | Microsoft Store ❌ | Mac App Store ❌ | Snap ❌  | Ubuntu ❌ |

Support for other app distributors is planned.

## Setup

### Android - Google Play Store (via Debian only)

1. Create an App in your [Google Play Console](https://play.google.com/console).
2. Make sure you have these files ignored in your `./android/.gitignore`:
   ```
   key.properties
   **/*.keystore
   **/*.jks

   # Google Play Store credentials
   fastlane-*.json
   play-store-credentials.json
   ```
3. Configure [signing in gradle](https://docs.flutter.dev/deployment/android#configure-signing-in-gradle).
   This is needed to be able to execute the build via Flutter and not via Gradle.
   Convert the keystore to a base64 string e.g. `base64 --wrap=0 android/keystore.jks`
4. Follow the guide of fastlane
   for [setting up supply](https://docs.fastlane.tools/getting-started/android/setup/#setting-up-supply).
5. Convert the Google Play Store credentials json to base64 e.g. `base64 --wrap=0 android/fastlane-secrets.json`
6. Manually build a signed app bundle and publish it on the Google Play Store at least once to be able to automate the
   process, e.g.:
   ```
   flutter build appbundle \
    --release \
    --build-name=0.0.1-beta.10 \
    --dart-define=API_URL=https://example.com \
    --dart-define=API_KEY=12345678
   ```

### iOS - App Store

1. Make sure you have these files ignored in your `./ios/.gitignore`:
   ```
   *.cer
   *.certSigningRequest
   *.mobileprovision
   *.p12
   *.p8
   ```
2. Create an [App Store connect API Team key](https://appstoreconnect.apple.com/access/integrations/api) with `App Manager` permissions.
   Copy the key into your `ios` folder. Also copy the `Key ID` and the `Issuer ID` for later.
3. Execute `flutter_release prepare ios`. Follow the steps.
   To delete existing certificates, visit: https://developer.apple.com/account/resources/certificates/list
4. Make sure the certificate is selected in the [App Store provisioning profile](https://developer.apple.com/account/resources/profiles/list)
5. Extract the information from the `ios/fastlane/Appfile` file.
6. Run flutter_release
   ```shell
   flutter_release publish ios-app-store \
    --dry-run \
    --app-name wrestling_scoreboard_client \
    --app-version v0.0.1-alpha.1 \
    --build-arg=--dart-define=API_URL=https://example.com \
    --build-arg=--dart-define=API_KEY=12345678 \
    --apple-username=<apple_id> \
    --api-key-id=<api-key-id> \
    --api-issuer-id=<api-issuer-id> \
    --api-private-key-base64=<api-private-key> \
    --content-provider-id=<itc_team_id> \
    --team-id=<team_id> \
    --distribution-private-key-base64=<distribution-private-key>
   ```
   Optionally add the `--team-enterprise` flag, if your team is in the Apple Developer Enterprise Program.

### Web - Server (via Debian only)

1. Generate a key pair on your client `ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519_flutter_release -C flutter_release` **without** a passphrase
2. Add the output of `cat $HOME/.ssh/id_ed25519_flutter_release.pub` to your servers `$HOME/.ssh/authorized_keys`
3. Convert the private key to a base64 string e.g. `base64 --wrap=0 $HOME/.ssh/id_ed25519_flutter_release`
4. Run flutter_release 
   ```shell
   flutter_release publish web-server \
    --dry-run \
    --app-name wrestling_scoreboard_client \
    --app-version v0.0.1-alpha.1 \
    --build-arg=--dart-define=API_URL=https://example.com \
    --build-arg=--dart-define=API_KEY=12345678 \
    --host=host.example.com \
    --path=/var/www/html \
    --ssh-port=22 \
    --ssh-user=<user> \
    --ssh-private-key-base64=<private-key>
   ```
