# CPU rvc unit test

Run from the repository root (create `build/unit` first):


Unified regression (from the repository root):

```sh
. ~/.local/opt/edrv32/env.sh
make smoke
```

`test.yaml` supplies simulator, ISA parameter and optional software selection;
`files.f` paths are relative to that file. Logs are under `build/regress/smoke/unit/`.
