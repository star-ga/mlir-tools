<p align="center">
  <img src="assets/mlir-tools.svg" width="96" height="96" alt="MLIR Tools logo">
</p>

# MLIR Tools

Pre-built `mlir-opt` and `mlir-translate` from the LLVM project, for the
optional MLIR backend of the [MIND](https://mindlang.dev) compiler (`mindc`).
Each release is built from a signed, checksum-pinned LLVM source release by one
script that you can run yourself.

## Status

- **The MIND native backend is the primary build path, and MLIR is optional.**
  `mindc build --backend native` lowers MIND straight to an x86-64 ELF with no
  MLIR, LLVM or clang involved, so it needs nothing from this repository. The
  MLIR backend is still needed for code the native backend does not lower yet
  (floats, tensors, GPU). In mindc 0.10.x the `--backend` flag still defaults
  to `mlir`, so pass `--backend native` explicitly.
- **Latest LLVM: 23.1.3.** The build is pinned and verified (`versions.txt`).
  Its release assets appear on the
  [releases page](https://github.com/star-ga/mlir-tools/releases) once the
  *Build MLIR Tools* workflow has run for `23.1.3`. Until then the newest
  published release is `llvmorg-21.1.8`.
- **MIND CI tests the MLIR backend with LLVM 20**, from Ubuntu's
  `mlir-20-tools` package. A move to LLVM 22/23 is in progress and has not
  landed in MIND CI yet. Until it does, LLVM 23 builds of these tools have not
  been tested against MIND. That is why `20.1.8` stays pinned here.

## Which tools for which mindc

| mindc | Build path | What you need |
|-------|------------|---------------|
| 0.10.x, `--backend native` | pure-MIND native backend (x86-64 ELF) | nothing from this repository |
| 0.10.x, `--backend mlir` (the flag's default), `--emit-obj`, `--emit-shared` | MLIR text, then `mlir-opt`, then `mlir-translate`, then `clang` | `mlir-opt` and `mlir-translate` from the same LLVM major as your `clang`. MIND CI uses LLVM 20 (`llvmorg-20.1.8` here). |
| 0.10.x, `check`, `--emit-ir`, `--emit-mlir` | front end only | nothing: the `mindc` binary works on its own |

This repository does not ship `clang`. Install it from your distribution or
from the official [LLVM release](https://github.com/llvm/llvm-project/releases)
with the same major version. According to the MIND install guide, MLIR 18
builds most programs but cannot bufferize a tensor carried across a loop or
returned from several exits.

### Pinned LLVM versions

| LLVM | Why it is pinned | Source signature | Sigstore provenance |
|------|------------------|------------------|---------------------|
| 23.1.3 | latest LLVM release | OpenPGP, key `D574 BD5D 1D0E 9889 5E3B F900 44F2 485E 45D5 9042` | yes |
| 20.1.8 | the LLVM major that MIND CI tests | OpenPGP, key `474E 2231 6ABF 4785 A88C 6E8E A2C7 94A9 8641 9D8A` | none published |

The 20.1.8 signature is valid, but the signing key's published expiry date is
earlier than the signature. The script prints a note when this happens, and the
pinned SHA-256 has to match too.

### Earlier releases

`llvmorg-21.1.8` and `llvmorg-18.1.8` came from an earlier workflow. That
workflow built from a git checkout, not a verified tarball, and published no
checksums. Two known defects affect both releases:

- `mlir-macos-x64.tar.gz` contains **arm64** binaries, not x86-64 ones. The
  runner it was built on (`macos-15`) is Apple Silicon.
- The macOS binaries load `/opt/homebrew/opt/zstd/lib/libzstd.1.dylib`, so they
  fail to start on a Mac without Homebrew's `zstd`.

Both defects are fixed for new builds: macOS x86-64 now builds on
`macos-15-intel`, and LLVM is configured with `-DLLVM_ENABLE_ZSTD=OFF`.

## Quick start

Download a release, check it, and put it on `PATH` (Linux and macOS):

```bash
VER=23.1.3           # an llvmorg-<VER> release from the releases page
PLAT=linux-x64       # linux-x64 | linux-arm64 | macos-x64 | macos-arm64
BASE=https://github.com/star-ga/mlir-tools/releases/download/llvmorg-$VER

curl -fsSLO "$BASE/mlir-$PLAT.tar.gz"
curl -fsSLO "$BASE/SHA256SUMS"
grep " mlir-$PLAT.tar.gz\$" SHA256SUMS | shasum -a 256 -c
gh attestation verify "mlir-$PLAT.tar.gz" --repo star-ga/mlir-tools

tar xzf "mlir-$PLAT.tar.gz"
export PATH="$PWD/mlir-$PLAT/bin:$PATH"
mlir-opt --version
```

Windows (PowerShell):

```powershell
$Ver = "23.1.3"
$Base = "https://github.com/star-ga/mlir-tools/releases/download/llvmorg-$Ver"
Invoke-WebRequest "$Base/mlir-windows-x64.zip" -OutFile mlir-windows-x64.zip
Invoke-WebRequest "$Base/SHA256SUMS" -OutFile SHA256SUMS
$Expected = (Select-String -Path SHA256SUMS -Pattern " mlir-windows-x64.zip$").Line.Split(" ")[0]
if ((Get-FileHash mlir-windows-x64.zip -Algorithm SHA256).Hash -ne $Expected.ToUpper()) { throw "checksum mismatch" }
Expand-Archive mlir-windows-x64.zip -DestinationPath .
$env:PATH = "$PWD\mlir-windows-x64\bin;$env:PATH"
mlir-opt --version
```

GitHub Actions:

```yaml
- name: Install MLIR tools
  env:
    VER: '23.1.3'
    GH_TOKEN: ${{ github.token }}
  run: |
    base=https://github.com/star-ga/mlir-tools/releases/download/llvmorg-$VER
    curl -fsSLO "$base/mlir-linux-x64.tar.gz"
    curl -fsSLO "$base/SHA256SUMS"
    grep ' mlir-linux-x64.tar.gz$' SHA256SUMS | sha256sum -c
    gh attestation verify mlir-linux-x64.tar.gz --repo star-ga/mlir-tools
    tar xzf mlir-linux-x64.tar.gz
    echo "$PWD/mlir-linux-x64/bin" >> "$GITHUB_PATH"
```

Each archive holds `bin/mlir-opt`, `bin/mlir-translate`, the LLVM
`LICENSE.TXT`, and `BUILD-INFO.txt`, which records the source tarball's
SHA-256 and signer.

## Build it yourself

`scripts/build-mlir-tools.sh` is the same script that CI runs. It:

1. downloads `llvm-project-<version>.src.tar.xz` and its `.sig` from the LLVM
   GitHub release;
2. checks the tarball's SHA-256 against `versions.txt`;
3. checks the OpenPGP signature against `keys/llvm-release-keys.asc` and
   requires the signing key that `versions.txt` names;
4. checks LLVM's sigstore provenance bundle with `gh attestation verify`, when
   the release publishes one and `gh` supports it (set
   `MLIR_TOOLS_ATTESTATION=require` to make this check mandatory);
5. builds `mlir-opt` and `mlir-translate` with fixed CMake flags, smoke-tests
   them, and writes `dist/mlir-<platform>.tar.gz` (`.zip` on Windows) with a
   `.sha256` file.

```bash
git clone https://github.com/star-ga/mlir-tools.git
cd mlir-tools
./scripts/build-mlir-tools.sh --version 23.1.3 --verify-only   # fetch and verify only
./scripts/build-mlir-tools.sh --version 23.1.3                 # verify and build for this host
./scripts/build-mlir-tools.sh --help
```

Requirements: `bash`, `curl`, `gpg`, `cmake` 3.20 or newer, `ninja`, and a C++
compiler (MSVC on Windows, run from Git Bash). Optional: a `gh` whose
`attestation verify` supports `--bundle` and `--source-ref`,
for the provenance check. A full LLVM build takes hours.

`keys/llvm-release-keys.asc` is a copy of
<https://releases.llvm.org/release-keys.asc>. When it was copied on
2026-10-09, its SHA-256 was
`f38bd19b7f2d22cafa755841e6ce9375b9a2e6d41f7b974e4953d6b084839001`.

### Adding an LLVM version

1. Download `llvm-project-<version>.src.tar.xz` and its `.sig`.
2. Check the signature against `keys/llvm-release-keys.asc`.
3. Add a line to `versions.txt` with the version, the SHA-256, the signer's
   fingerprint, and `sigstore` or `none`.

The script refuses any version that is not in `versions.txt`.

### Publishing a release

Go to **Actions → Build MLIR Tools → Run workflow** and enter a pinned version.
You can also choose a subset of platforms; such a run only uploads workflow
artifacts, and a release is published only when all platforms are built. The
workflow:

- verifies the source once;
- builds every selected platform from the same script;
- publishes `llvmorg-<version>` with the archives and `SHA256SUMS`;
- records a GitHub build-provenance attestation for each archive.

| Platform | Runner |
|----------|--------|
| `linux-x64` | `ubuntu-22.04` |
| `linux-arm64` | `ubuntu-22.04-arm` |
| `macos-x64` | `macos-15-intel` |
| `macos-arm64` | `macos-15` |
| `windows-x64` | `windows-2025` |

## How MIND uses these tools

`mindc`'s MLIR backend writes MLIR text, runs it through
`mlir-opt` and `mlir-translate` to get LLVM IR, and compiles that with `clang`.
It looks for the tools on `PATH`. If one is missing, the build stops with a
`tool not found` error that names it, rather than falling back to anything
else. The native backend uses none of these tools. See
[MLIR Lowering](https://mindlang.dev/docs/mlir) and the
[MIND install guide](https://github.com/star-ga/mind/blob/main/docs/install.md).

## License

`mlir-opt`, `mlir-translate`, and LLVM itself are part of the LLVM Project,
licensed under the Apache License v2.0 with LLVM Exceptions. The scripts and
workflows in this repository use the same license. See [LICENSE](LICENSE).

## Links

- MIND language: <https://mindlang.dev>
- MIND compiler: <https://github.com/star-ga/mind>
- MLIR: <https://mlir.llvm.org/>
- LLVM releases: <https://github.com/llvm/llvm-project/releases>
