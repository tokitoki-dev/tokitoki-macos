#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# The pin and both digests are reviewed together. Environment overrides are
# intentionally not accepted: changing the CLI bundled by an app release must
# be a visible repository change that goes through the protected main branch.
. "$SCRIPT_DIR/cli-release-pins.sh"

OUT_DIR="$PROJECT_DIR/.build/cli"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/tokitoki-cli-release.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if ! printf '%s\n' "$TOKITOKI_CLI_TAG" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "error: invalid pinned CLI tag: $TOKITOKI_CLI_TAG" >&2
  exit 1
fi

for digest in \
  "$TOKITOKI_CLI_DARWIN_AMD64_SHA256" \
  "$TOKITOKI_CLI_DARWIN_ARM64_SHA256"; do
  if ! printf '%s\n' "$digest" | grep -Eq '^[0-9a-f]{64}$'; then
    echo "error: invalid pinned CLI SHA-256: $digest" >&2
    exit 1
  fi
done

BASE_URL="https://github.com/tokitoki-dev/tokitoki-cli/releases/download/$TOKITOKI_CLI_TAG"

fetch_and_verify() {
  asset="$1"
  expected_arch="$2"
  expected_sha256="$3"
  destination="$TMP/$asset"

  curl --fail --location --silent --show-error --retry 3 \
    --proto '=https' --proto-redir '=https' \
    --output "$destination" "$BASE_URL/$asset"

  printf '%s  %s\n' "$expected_sha256" "$destination" | shasum -a 256 -c -
  actual_arch="$(lipo -archs "$destination")"
  if [ "$actual_arch" != "$expected_arch" ]; then
    echo "error: $asset contains '$actual_arch', expected '$expected_arch'" >&2
    exit 1
  fi
  chmod 755 "$destination"
}

fetch_and_verify \
  tokitoki-darwin-amd64 x86_64 "$TOKITOKI_CLI_DARWIN_AMD64_SHA256"
fetch_and_verify \
  tokitoki-darwin-arm64 arm64 "$TOKITOKI_CLI_DARWIN_ARM64_SHA256"

# Run the host-native asset as a second, independent check that the release
# behind the pinned tag reports the version the app expects to bundle.
case "$(uname -m)" in
  arm64) native="$TMP/tokitoki-darwin-arm64" ;;
  x86_64) native="$TMP/tokitoki-darwin-amd64" ;;
  *)
    echo "error: unsupported build host architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

got_version="$("$native" version)"
expected_version="${TOKITOKI_CLI_TAG#v}"
if [ "$got_version" != "$expected_version" ]; then
  echo "error: CLI reports '$got_version', pinned tag is '$expected_version'" >&2
  exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
mv "$TMP/tokitoki-darwin-amd64" "$OUT_DIR/"
mv "$TMP/tokitoki-darwin-arm64" "$OUT_DIR/"

echo "Fetched Tokitoki CLI $expected_version for amd64 and arm64."
