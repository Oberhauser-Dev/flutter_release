# dart_release example

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
