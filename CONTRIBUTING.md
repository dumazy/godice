# Contributing

## Setup

```sh
fvm install                          # Flutter/Dart version from .fvmrc
fvm dart pub global activate melos
melos bootstrap                      # `flutter pub get` for the workspace
```

Day-to-day commands (all run from the repository root):

| Command | What it does |
|---|---|
| `melos run analyze` | `dart analyze --fatal-infos` on the whole workspace |
| `melos run format` | formatting check for the packages we own |
| `melos run test` | Dart tests (`godice`) and Flutter tests (`godice_universal_ble`) |
| `melos run publish:dry-run` | pub.dev validation of the publishable packages |
| `melos run smoke-test` | lists nearby dice with the pure Dart CLI (needs hardware + `tool/build_native.sh`) |
| `melos list` | shows every package and whether it is private |

CI runs the first four on every push and pull request, plus
`tool/check_min_sdk.sh` on the oldest Flutter the packages claim to support
(the `flutter: ">=..."` floor in their pubspecs). Run that locally with
`fvm spawn 3.32.0 bash tool/check_min_sdk.sh` before lowering or raising the
floor.

## Repository layout

| Path | Published? | Purpose |
|---|---|---|
| `packages/godice` | yes | protocol + transport-agnostic client |
| `packages/godice_universal_ble` | yes | Flutter transport on `universal_ble`, with `example/` app |
| `tools/godice_bluetooth_dart` | no | pure Dart transport used by the smoke test |
| `tools/godice_cli` | no | terminal smoke test against real dice |
| `third_party/bluetooth_dart` | no | vendored `bluetooth_dart` 0.0.1 with a local fix |

Only packages under `packages/` are ever published. Everything else carries
`publish_to: none` and Melos skips it when publishing.

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org) so
`melos version` can derive version bumps and changelogs:

- `fix(godice): …` → patch
- `feat(godice_universal_ble): …` → minor
- `feat!: …` or a `BREAKING CHANGE:` footer → major (minor while `0.x`)

## Releasing

1. Make sure `main` is green.
2. Run `melos version`. Melos looks at the commits since the last tag of each
   package, proposes bumps, updates `pubspec.yaml` and `CHANGELOG.md`,
   commits, and creates one tag per package (`godice-v0.2.0`,
   `godice_universal_ble-v0.2.0`). Use `melos version --no-git-tag-version`
   if you prefer to review the commit first, or `melos version godice patch`
   to bump one package explicitly.
3. `git push --follow-tags`.
4. The **Publish** workflow runs once per tag and publishes that package with
   `flutter pub publish --force`, authenticated through GitHub's OIDC token.

### pub.dev setup (done for the current packages)

Both packages are owned by the verified publisher `skystoneapps.com`.
Automated publishing from GitHub Actions is enabled on each package's admin
page with repository `dumazy/godice`, tag pattern `<package>-v{{version}}`,
push events only (no `workflow_dispatch`, no required environment).

For a *new* package: publish the first version by hand from its directory,
transfer it to the publisher from its admin page, enable automated
publishing as above, add its tag pattern to `.github/workflows/publish.yml`,
and tag the published version (`git tag <package>-v<version>`) so
`melos version` has a baseline.

### Publishing order

`godice_universal_ble` depends on `godice`. When both change, publish
`godice` first and wait for pub.dev to serve the new version before pushing
the `godice_universal_ble` tag, or the second publish fails to resolve its
dependency.
