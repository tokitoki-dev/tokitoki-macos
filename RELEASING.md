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
| The binaries | GitHub Releases of `akarineren/tracklm-macos` | no |

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

### 1. Bump the version

`MARKETING_VERSION` in the Xcode project. It **must be semver** (`1.3.0`, not
`1.3`) — the server compares versions and refuses to parse anything else, so a
two-component version is a release nobody is ever offered.

### 2. Build, sign, notarize

The app must be Developer ID signed *and notarized*, or Gatekeeper blocks the
update Sparkle installs and the user sees a broken app instead of a new one.

```sh
xcodebuild -project tracklm-macos.xcodeproj -scheme tracklm-macos \
  -configuration Release -archivePath build/TokiToki.xcarchive archive

xcodebuild -exportArchive -archivePath build/TokiToki.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export

# Notarize, then staple the ticket to the app.
xcrun notarytool submit build/export/TokiToki.app --wait \
  --keychain-profile "AC_PASSWORD"
xcrun stapler staple build/export/TokiToki.app
```

### 3. Package and sign for Sparkle

The filename must say which architecture it is for — the server matches assets
to machines by name (`arm64` / `aarch64`, `amd64` / `x86_64` / `intel`), and an
asset it cannot place is an asset nobody is offered.

```sh
hdiutil create -srcfolder build/export -volname TokiToki \
  -format UDZO "TokiToki-1.3.0-arm64.dmg"

# The signature. Prints one base64 line; that line is the whole security model.
./bin/sign_update -p "TokiToki-1.3.0-arm64.dmg" > "TokiToki-1.3.0-arm64.dmg.sig"
```

`sign_update` reads the private key from the Keychain and will prompt for
access. `-p` prints only the signature, which is what belongs in the `.sig`.

### 4. Upload both files to the GitHub Release

The `.sig` **must** sit next to its binary and be named `<binary>.sig` exactly:

```
TokiToki-1.3.0-arm64.dmg
TokiToki-1.3.0-arm64.dmg.sig
TokiToki-1.3.0-amd64.dmg
TokiToki-1.3.0-amd64.dmg.sig
```

The signature lives beside the binary rather than in our database because it is
*derived from* the binary. A signature kept apart from the thing it signs is a
signature that can go stale, and a stale signature is an update that silently
stops installing.

A `.dmg` uploaded without its `.sig` is not an error you will see — the release
simply never appears in the appcast. If a version you published is not reaching
anyone, look for a missing `.sig` first.

### 5. Publish it

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

To sign in CI, put the exported private key in a GitHub secret
(`SPARKLE_PRIVATE_KEY`) and feed it to `sign_update` directly, which needs no
Keychain:

```yaml
- run: |
    echo "${{ secrets.SPARKLE_PRIVATE_KEY }}" > /tmp/sparkle_key
    ./bin/sign_update -p --ed-key-file /tmp/sparkle_key "$DMG" > "$DMG.sig"
    rm /tmp/sparkle_key
```
