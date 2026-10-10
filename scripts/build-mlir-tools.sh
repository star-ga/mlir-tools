#!/usr/bin/env bash
# Fetch a signed LLVM source release, verify it, and build mlir-opt and
# mlir-translate from it.
#
# The same script runs locally and in .github/workflows/build-mlir.yml, so a
# release asset can be rebuilt from the same pinned inputs and the same flags.
# Runs on Linux, macOS and Windows (Git Bash, with MSVC on PATH).
#
# Requirements: bash, curl, gpg, cmake (3.20+), ninja, a C++ compiler.
# Optional: gh with "attestation verify --bundle --source-ref" for the sigstore
# provenance check.

set -euo pipefail

LLVM_REPO="llvm/llvm-project"
DOWNLOAD_BASE="https://github.com/${LLVM_REPO}/releases/download"
TOOLS="mlir-opt mlir-translate"

usage() {
  cat <<'EOF'
Usage: scripts/build-mlir-tools.sh [options]

Options:
  --version V      LLVM version to build (default: first entry in versions.txt)
  --platform P     linux-x64 | linux-arm64 | macos-x64 | macos-arm64 | windows-x64
                   (default: detected from the host)
  --workdir DIR    download, extract and build here (default: ./work)
  --outdir DIR     write the packaged archive and its .sha256 here (default: ./dist)
  --jobs N         parallel build jobs (default: number of CPUs)
  --verify-only    fetch and verify the source tarball, then stop
  -h, --help       show this help

Environment:
  MLIR_TOOLS_ATTESTATION=require   fail unless the sigstore provenance check runs and passes
  MLIR_TOOLS_ATTESTATION=skip      do not run the sigstore provenance check
  (default: run it when versions.txt says one exists and gh supports it)
EOF
}

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*" >&2; }

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PINS="${REPO_ROOT}/versions.txt"
KEYS="${REPO_ROOT}/keys/llvm-release-keys.asc"

VERSION=""
PLATFORM=""
WORKDIR="${PWD}/work"
OUTDIR="${PWD}/dist"
JOBS=""
VERIFY_ONLY=0
ATTESTATION="${MLIR_TOOLS_ATTESTATION:-auto}"

while [ $# -gt 0 ]; do
  case "$1" in
    --version) VERSION="${2:?--version needs a value}"; shift 2 ;;
    --platform) PLATFORM="${2:?--platform needs a value}"; shift 2 ;;
    --workdir) WORKDIR="${2:?--workdir needs a value}"; shift 2 ;;
    --outdir) OUTDIR="${2:?--outdir needs a value}"; shift 2 ;;
    --jobs) JOBS="${2:?--jobs needs a value}"; shift 2 ;;
    --verify-only) VERIFY_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

case "$ATTESTATION" in
  auto|require|skip) ;;
  *) die "MLIR_TOOLS_ATTESTATION must be auto, require or skip (got '$ATTESTATION')" ;;
esac

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not on PATH"; }

# ---- pinned inputs ---------------------------------------------------------

[ -f "$PINS" ] || die "missing $PINS"
[ -f "$KEYS" ] || die "missing $KEYS"

if [ -z "$VERSION" ]; then
  VERSION="$(awk '!/^#/ && NF { print $1; exit }' "$PINS")"
fi
case "$VERSION" in
  llvmorg-*) VERSION="${VERSION#llvmorg-}" ;;
esac
case "$VERSION" in
  *[!0-9.]*|"") die "invalid LLVM version '$VERSION' (expected e.g. 23.1.3)" ;;
esac

PIN_LINE="$(awk -v v="$VERSION" '!/^#/ && $1 == v { print; exit }' "$PINS")"
[ -n "$PIN_LINE" ] || die "LLVM $VERSION is not pinned in versions.txt; verify its tarball and add a line first"
# shellcheck disable=SC2086
set -- $PIN_LINE
[ $# -eq 4 ] || die "malformed versions.txt line for $VERSION"
EXPECTED_SHA256="$2"
EXPECTED_SIGNER="$3"
PIN_ATTESTATION="$4"

detect_platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Linux) os=linux ;;
    Darwin) os=macos ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *) die "unsupported host OS: $os" ;;
  esac
  case "$arch" in
    x86_64|amd64) arch=x64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) die "unsupported host architecture: $arch" ;;
  esac
  echo "${os}-${arch}"
}

[ -n "$PLATFORM" ] || PLATFORM="$(detect_platform)"
case "$PLATFORM" in
  linux-x64|linux-arm64|macos-x64|macos-arm64|windows-x64) ;;
  *) die "unsupported platform '$PLATFORM'" ;;
esac

# ---- fetch -----------------------------------------------------------------

require_cmd curl
require_cmd gpg
require_cmd cmake

TARBALL="llvm-project-${VERSION}.src.tar.xz"
SRC_URL="${DOWNLOAD_BASE}/llvmorg-${VERSION}/${TARBALL}"
DL_DIR="${WORKDIR}/downloads"
mkdir -p "$DL_DIR"

fetch() {
  local url="$1" dest="$2"
  if [ -s "$dest" ]; then
    log "using cached $(basename "$dest")"
    return 0
  fi
  log "downloading $url"
  curl -fL --retry 3 --retry-delay 5 -o "${dest}.part" "$url" || die "download failed: $url"
  mv "${dest}.part" "$dest"
}

fetch "$SRC_URL" "${DL_DIR}/${TARBALL}"
fetch "${SRC_URL}.sig" "${DL_DIR}/${TARBALL}.sig"

# ---- verify ----------------------------------------------------------------

sha256_of() { cmake -E sha256sum "$1" | awk '{ print $1 }'; }

log "checking SHA-256 of ${TARBALL}"
ACTUAL_SHA256="$(sha256_of "${DL_DIR}/${TARBALL}")"
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
  die "SHA-256 mismatch for ${TARBALL}: expected ${EXPECTED_SHA256}, got ${ACTUAL_SHA256}"
fi

log "checking OpenPGP signature of ${TARBALL}"
GPG_HOME="$(mktemp -d)"
trap 'rm -rf "$GPG_HOME"' EXIT
gpg --homedir "$GPG_HOME" --batch --quiet --import "$KEYS" 2>/dev/null \
  || die "could not import $KEYS"
GPG_STATUS="$(gpg --homedir "$GPG_HOME" --batch --status-fd 1 \
  --verify "${DL_DIR}/${TARBALL}.sig" "${DL_DIR}/${TARBALL}" 2>/dev/null)" \
  || die "OpenPGP signature check failed for ${TARBALL}"
SIGNER="$(printf '%s\n' "$GPG_STATUS" | awk '$2 == "VALIDSIG" { print $NF; exit }')"
if [ "$SIGNER" != "$EXPECTED_SIGNER" ]; then
  die "${TARBALL} is signed by '${SIGNER:-nobody}', expected ${EXPECTED_SIGNER}"
fi
if printf '%s\n' "$GPG_STATUS" | grep -q 'EXPKEYSIG'; then
  log "note: signing key ${SIGNER} is past its published expiry date; signature is cryptographically valid and the SHA-256 pin matches"
fi
log "signature OK (key ${SIGNER})"

verify_attestation() {
  local bundle="${DL_DIR}/${TARBALL}.jsonl"
  if [ "$ATTESTATION" = skip ]; then
    log "sigstore provenance check skipped (MLIR_TOOLS_ATTESTATION=skip)"
    return 0
  fi
  if [ "$PIN_ATTESTATION" != sigstore ]; then
    [ "$ATTESTATION" = require ] && die "LLVM ${VERSION} publishes no sigstore bundle"
    log "LLVM ${VERSION} publishes no sigstore bundle; relying on the OpenPGP signature"
    return 0
  fi
  local gh_help=""
  if command -v gh >/dev/null 2>&1; then
    gh_help="$(gh attestation verify --help 2>/dev/null || true)"
  fi
  case "$gh_help" in
    *--bundle*--source-ref*|*--source-ref*--bundle*) ;;
    *)
      [ "$ATTESTATION" = require ] && die "gh with 'attestation verify --bundle --source-ref' is required"
      log "gh with 'attestation verify --bundle --source-ref' not found; skipping the sigstore provenance check"
      return 0
      ;;
  esac
  fetch "${SRC_URL}.jsonl" "$bundle"
  log "checking sigstore provenance of ${TARBALL}"
  gh attestation verify "${DL_DIR}/${TARBALL}" \
    --repo "$LLVM_REPO" \
    --source-ref "refs/tags/llvmorg-${VERSION}" \
    --bundle "$bundle" >/dev/null \
    || die "sigstore provenance check failed for ${TARBALL}"
  log "provenance OK (built by ${LLVM_REPO} at llvmorg-${VERSION})"
}
verify_attestation

if [ "$VERIFY_ONLY" -eq 1 ]; then
  log "verified LLVM ${VERSION} source; stopping (--verify-only)"
  exit 0
fi

# ---- extract ---------------------------------------------------------------

require_cmd ninja
SRC_DIR="${WORKDIR}/llvm-project-${VERSION}.src"
if [ ! -f "${SRC_DIR}/.extracted" ]; then
  log "extracting ${TARBALL}"
  rm -rf "$SRC_DIR"
  (cd "$WORKDIR" && cmake -E tar xf "downloads/${TARBALL}") || die "extraction failed"
  [ -d "${SRC_DIR}/llvm" ] || die "unexpected tarball layout: ${SRC_DIR}/llvm missing"
  : > "${SRC_DIR}/.extracted"
fi

# ---- configure and build ---------------------------------------------------

if [ -z "$JOBS" ]; then
  JOBS="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "${NUMBER_OF_PROCESSORS:-4}")"
fi

BUILD_DIR="${WORKDIR}/build-${VERSION}-${PLATFORM}"
# LLVM_ENABLE_ZSTD=OFF: otherwise the binaries link whatever libzstd the build
# host has (a Homebrew path on macOS), and fail to start where it is absent.
CMAKE_ARGS="
  -DLLVM_ENABLE_PROJECTS=mlir
  -DLLVM_TARGETS_TO_BUILD=X86;AArch64
  -DCMAKE_BUILD_TYPE=Release
  -DLLVM_ENABLE_ASSERTIONS=OFF
  -DLLVM_ENABLE_ZSTD=OFF
  -DLLVM_BUILD_EXAMPLES=OFF
  -DLLVM_BUILD_TESTS=OFF
  -DMLIR_BUILD_MLIR_C_DYLIB=OFF
"
case "$PLATFORM" in
  windows-*) CMAKE_ARGS="$CMAKE_ARGS -DCMAKE_C_COMPILER=cl -DCMAKE_CXX_COMPILER=cl" ;;
esac

log "configuring LLVM ${VERSION} for ${PLATFORM}"
# shellcheck disable=SC2086
cmake -G Ninja -S "${SRC_DIR}/llvm" -B "$BUILD_DIR" $CMAKE_ARGS || die "configure failed"

log "building ${TOOLS} with ${JOBS} jobs"
# shellcheck disable=SC2086
cmake --build "$BUILD_DIR" --target $TOOLS -j "$JOBS" || die "build failed"

# ---- package ---------------------------------------------------------------

EXE=""
case "$PLATFORM" in windows-*) EXE=".exe" ;; esac

PKG="mlir-${PLATFORM}"
STAGE="${WORKDIR}/stage-${VERSION}/${PKG}"
rm -rf "$STAGE"
mkdir -p "${STAGE}/bin"
for tool in $TOOLS; do
  cp "${BUILD_DIR}/bin/${tool}${EXE}" "${STAGE}/bin/"
done
cp "${SRC_DIR}/mlir/LICENSE.TXT" "${STAGE}/LICENSE.TXT"
{
  echo "LLVM ${VERSION}"
  echo "source ${TARBALL} sha256 ${EXPECTED_SHA256}"
  echo "signed-by ${EXPECTED_SIGNER}"
  echo "platform ${PLATFORM}"
} > "${STAGE}/BUILD-INFO.txt"

log "smoke test"
"${STAGE}/bin/mlir-opt${EXE}" --version >/dev/null || die "mlir-opt does not run"
"${STAGE}/bin/mlir-translate${EXE}" --version >/dev/null || die "mlir-translate does not run"

mkdir -p "$OUTDIR"
OUTDIR="$(cd "$OUTDIR" && pwd)"
case "$PLATFORM" in
  windows-*) ARCHIVE="${PKG}.zip"; TAR_FLAGS="cf"; FORMAT="--format=zip" ;;
  *) ARCHIVE="${PKG}.tar.gz"; TAR_FLAGS="czf"; FORMAT="" ;;
esac
rm -f "${OUTDIR}/${ARCHIVE}"
# shellcheck disable=SC2086
(cd "$(dirname "$STAGE")" && cmake -E tar "$TAR_FLAGS" "${OUTDIR}/${ARCHIVE}" $FORMAT "$PKG") \
  || die "packaging failed"
(cd "$OUTDIR" && echo "$(sha256_of "$ARCHIVE")  ${ARCHIVE}" > "${ARCHIVE}.sha256")

log "wrote ${OUTDIR}/${ARCHIVE}"
cat "${OUTDIR}/${ARCHIVE}.sha256"
