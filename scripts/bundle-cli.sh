#!/bin/sh

set -eu

# Xcode launched from Finder does not inherit a developer shell's PATH.
# Honour an explicit override, then look in the standard macOS Go locations.
GO_BIN="${TOKITOKI_GO_BIN:-}"
if [ -z "$GO_BIN" ]; then
  GO_BIN="$(command -v go 2>/dev/null || true)"
fi
if [ -z "$GO_BIN" ] && [ -x /opt/homebrew/bin/go ]; then
  GO_BIN=/opt/homebrew/bin/go
fi
if [ -z "$GO_BIN" ] && [ -x /usr/local/go/bin/go ]; then
  GO_BIN=/usr/local/go/bin/go
fi
if [ -z "$GO_BIN" ] || [ ! -x "$GO_BIN" ]; then
  echo "error: Go is required to bundle Tokitoki. Install Go or set TOKITOKI_GO_BIN." >&2
  exit 1
fi

VERSION="${TOKITOKI_CLI_VERSION:-dev}"
LDFLAGS="-X github.com/tokitoki-dev/tokitoki-cli/internal/buildinfo.Version=$VERSION"
OUT="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/tokitoki"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
cd "$PROJECT_DIR/../tokitoki-cli"

build_slice() {
  xcode_arch="$1"
  go_arch="$2"
  destination="$TMP/$xcode_arch"

  if [ "${CONFIGURATION:-Debug}" = Release ]; then
    # Strip Go's symbol/debug tables and local build paths from distributable
    # binaries. Runtime stack traces remain available, while the compressed CLI
    # is roughly half the size of the previous unstripped universal binary.
    CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" "$GO_BIN" build \
      -trimpath -buildvcs=false -ldflags "-s -w $LDFLAGS" \
      -o "$destination" ./cmd/tokitoki
  else
    CGO_ENABLED=0 GOOS=darwin GOARCH="$go_arch" "$GO_BIN" build \
      -ldflags "$LDFLAGS" -o "$destination" ./cmd/tokitoki
  fi
}

arm64_slice=
x86_64_slice=
for arch in ${ARCHS:-}; do
  case "$arch" in
    arm64)
      build_slice arm64 arm64
      arm64_slice="$TMP/arm64"
      ;;
    x86_64)
      build_slice x86_64 amd64
      x86_64_slice="$TMP/x86_64"
      ;;
    *)
      echo "error: unsupported Xcode architecture for bundled CLI: $arch" >&2
      exit 1
      ;;
  esac
done

if [ -n "$arm64_slice" ] && [ -n "$x86_64_slice" ]; then
  lipo -create -output "$TMP/tokitoki" "$arm64_slice" "$x86_64_slice"
elif [ -n "$arm64_slice" ]; then
  cp "$arm64_slice" "$TMP/tokitoki"
elif [ -n "$x86_64_slice" ]; then
  cp "$x86_64_slice" "$TMP/tokitoki"
else
  echo "error: Xcode did not provide any architectures in ARCHS" >&2
  exit 1
fi

# Notarization rejects unsigned Mach-O files in an app bundle. Xcode does not
# sign a bare executable in Resources, so sign the completed CLI before copying
# it to the declared build output. Local unsigned builds use an ad-hoc identity.
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
  codesign --force --sign - "$TMP/tokitoki"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$TMP/tokitoki"
fi
cp -f "$TMP/tokitoki" "$OUT"
