# dart_release

A tool for building and publishing Flutter apps, e.g. on GitHub, the Google Play Store and Apple's App Store.
See also the according [GitHub action](https://github.com/marketplace/actions/flutter-release-action).

## Example

Build:

```shell
dart_release build \
 --main-path "bin/example.dart"
 --app-name example \
 --app-version v0.0.1-alpha.1 \
 --build-arg=--define=DB_USER=user \
 --build-arg=--define=DB_PASSWORD=12345678 \
 --include-path README.md
```

If the command is not found (in the PATH), try: `dart pub global run dart_release ...`.

Note that you have to pass the base64 arguments without any newline characters:

```shell
MY_BASE_64=$(base64 --wrap=0 /myfile)
```

Or remove them afterward:

```shell
MY_BASE_64="${MY_BASE_64//$'\n'/}"
```

## Options:

- `main-path`: The Dart entry point
- `app-name`: The name of the app executable
- `app-version`: Semantic version of the release (like `v1.2.3`), see https://semver.org/

## Supported Features

| Platform    | Windows           | macOS        | Linux          |
|-------------|-------------------|--------------|----------------|
| **Build**   | windows           | macos        | linux          |
| **Publish** | Microsoft Store ❌ | Home Brew ❌  | Snap ❌         |
| **Deploy**  | Windows Server ❌  | Mac Server ❌ | Linux Server ✓ |

Support for other app distributors is planned.

## Deploy Setup

1. Generate a key pair on your client `ssh-keygen -t ed25519 -f $HOME/.ssh/id_ed25519_dart_release -C dart_release` *
   *without** a passphrase
2. Add the output of `cat $HOME/.ssh/id_ed25519_dart_release.pub` to your servers `$HOME/.ssh/authorized_keys`
3. Convert the private key to a base64 string e.g. `base64 --wrap=0 $HOME/.ssh/id_ed25519_dart_release`
4. Run dart_release
   ```shell
   dart_release deploy \
    --dry-run \
    --app-name example \
    --app-version v0.0.1-alpha.1 \
    --build-arg=--define=DB_USER=user \
    --build-arg=--define=DB_PASSWORD=12345678 \
    --host=host.example.com \
    --path=.local/share/example/ \
    --ssh-port=22 \
    --ssh-user=<user> \
    --ssh-private-key-base64=<private-key> \
    --main-path bin/example.dart \
    --include-path public \
    --include-path .env.example \
    --pre-script deploy-pre-run.sh \
    --post-script deploy-post-run.sh
   ```
