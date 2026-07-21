# Releasing TokiToki for macOS

The app updates itself with [Sparkle](https://sparkle-project.org). Sparkle will
only install a build whose **EdDSA signature** verifies against the public key
compiled into the copy already on the user's machine — so a release is not
"shipped" until it is signed, and a release published without its signature is
simply invisible to every client.

That is deliberate: an update the app would refuse is worse than no update at
all. It is an updater that reports failure forever.

## The pieces

| Thing | Where it lives | Secret? |
| --- | --- | --- |
| EdDSA **private** key | your login Keychain (account `ed25519`) | **yes — never commit, never paste** |
| EdDSA **public** key | `TOKITOKI_SPARKLE_PUBLIC_KEY` in the Xcode build settings | no |
| Which versions ship | the `/admin/releases` page | — |
| The binaries | GitHub Releases of `tokitoki-dev/tokitoki-macos` | no |

The public key currently baked into the app is:

```
LD6FHlOZA+8LyHG+YSoLq5iFXZz70PAYO5WynhBomFY=
```

### Back up the private key. Now.

It is the root of trust for every macOS update you will ever ship.

- **Lose it** and every installed copy stops accepting updates *permanently*.
  There is no recovery: the only fix is getting each user to manually download a
  new build carrying a new public key.
- **Leak it** and anyone can sign an update your users' machines will trust and
  install without asking.

Export it once and put it somewhere safe (a password manager):

```sh
./bin/generate_keys -x sparkle_private_key.txt   # prompts for Keychain access
# store the contents somewhere safe, then:
rm sparkle_private_key.txt
```

## Cutting a release

GitHub Actions does the mechanical work. Cutting a release is two commands and
one admin click:

```sh
# Create release tags only from an up-to-date main branch.
git switch main
git pull --ff-only
git tag v1.3.0        # must be semver — the server refuses anything else
git push origin v1.3.0
```

The `Release` workflow (`.github/workflows/release.yml`) first rejects any tag
whose commit is not part of `main`, then runs the unit tests. On success, a
macOS runner checks out `tokitoki-cli` at the explicitly pinned
`TOKITOKI_CLI_TAG` as the sibling the Xcode project expects, builds the archive
with `MARKETING_VERSION` **and**
`CURRENT_PROJECT_VERSION` set to the tag (Sparkle compares the appcast's
`sparkle:version` against the installed `CFBundleVersion`, so both must be the
semver), Developer ID signs it, notarizes and staples it, verifies the signature
and both `arm64` and `x86_64` slices, packages the two DMGs, Sparkle-signs them,
and publishes the GitHub release:

```
TokiToki-1.3.0-arm64.dmg
TokiToki-1.3.0-arm64.dmg.sig
TokiToki-1.3.0-amd64.dmg
TokiToki-1.3.0-amd64.dmg.sig
```

The filenames carry the arch because the server matches assets to machines by
name (`arm64` / `aarch64`, `amd64` / `x86_64` / `intel`). The `.sig` sits next
to its binary because it is *derived from* the binary — a signature kept apart
from the thing it signs can go stale, and a stale signature is an update that
silently stops installing. A `.dmg` without its `.sig` is not an error you will
see: the release simply never appears in the appcast.

### One-time setup: repository secrets

The workflow needs these secrets (Settings → Secrets and variables → Actions);
without any one of them the release job fails:

| Secret | Contents |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | base64 of the Developer ID Application certificate (.p12) |
| `MACOS_CERTIFICATE_PASSWORD` | the .p12's password |
| `KEYCHAIN_PASSWORD` | any string; protects the runner's throwaway keychain |
| `AC_API_KEY_P8` | App Store Connect API key file contents (for notarytool) |
| `AC_API_KEY_ID` | that key's ID |
| `AC_API_ISSUER_ID` | that key's issuer ID |
| `SPARKLE_PRIVATE_KEY` | `generate_keys -x` output — the same EdDSA private key as in your Keychain |

Export the certificate: Keychain Access → Developer ID Application → export as
.p12, then `base64 -i cert.p12 | pbcopy`.

### Publish it

In `/admin/releases`: import the tag, then turn on **Published**. Set **Rollout**
below 100 to stage it (note: Sparkle's feed only carries fully rolled-out
releases — a partial rollout is served to the JSON updater, not to Sparkle).
**Mandatory** makes it a Sparkle *critical update*: shown promptly, cannot be
skipped.

Nothing reaches a user until this step. Importing a tag is bookkeeping;
publishing is the decision.

## How the client finds it

The app has **no `SUFeedURL`** in its Info.plist. It ships as one universal
binary but an appcast describes one architecture, so the feed URL cannot be a
build-time constant — `Updater.swift` builds it at runtime from the architecture
the process is actually executing as:

```
<server>/api/updates/appcast/macos/{arm64|amd64}
```

Using the *process* architecture, not the machine's, is what makes this correct
under Rosetta: a translated x86_64 app on Apple Silicon must be offered the
Intel build, because that is what it is.

Downloads go through `<server>/api/updates/download/...`, which streams the
bytes from GitHub through our server rather than redirecting to it — GitHub's
release CDN is not reliably reachable from mainland China, so a redirect there
would strand those users mid-update. The client only ever talks to our host,
the published/unpublished decision keeps applying to the bytes themselves, and
the proxy copies bytes unaltered, so the EdDSA signature still verifies.

## CI

Daily work is pushed to `dev`, which intentionally triggers no workflow. A pull
request whose base is `main` runs the unsigned build and unit tests, and merging
it runs the same checks once more on `main`. Direct pushes to `main` are blocked
by the repository's branch protection settings.

Before cutting an app release that updates the bundled CLI, update
`TOKITOKI_CLI_TAG` in `.github/workflows/release.yml` through the same pull
request flow. Pinning the CLI makes a rebuild of an existing app tag use the
same source inputs instead of silently selecting a newer CLI release.

To sign in CI, put the exported private key in a GitHub secret
(`SPARKLE_PRIVATE_KEY`) and feed it to `sign_update` directly, which needs no
Keychain:

```yaml
- run: |
    echo "${{ secrets.SPARKLE_PRIVATE_KEY }}" > /tmp/sparkle_key
    ./bin/sign_update -p --ed-key-file /tmp/sparkle_key "$DMG" > "$DMG.sig"
    rm /tmp/sparkle_key
```
