# Dart Packages

Collection of Dart and Flutter packages.

## Development

_Dart Packages_ is a monorepo.
Therefor it uses [Melos](https://github.com/invertase/melos) to manage the project and dependencies.
All the commands can be found in the [melos.yaml](melos.yaml) file.

To install Melos, run the following command from your terminal:

```bash
flutter pub global activate melos
```

Next, at the root of your locally cloned repository bootstrap the projects dependencies:

```bash
melos bs
```

To format your code, call:
```bash
melos format
```

To create a new version of all packages, call:
```bash
melos version
```

## License

Published under [MIT license](./LICENSE.md).
