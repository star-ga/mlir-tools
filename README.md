# MLIR Tools

Pre-built [MLIR](https://mlir.llvm.org/) tools from the LLVM project for use in CI/CD pipelines.

## Overview

This repository provides pre-compiled MLIR binaries for multiple platforms, eliminating the need to build LLVM/MLIR from source in your CI workflows.

## Included Tools

| Tool | Description |
|------|-------------|
| `mlir-opt` | MLIR optimizer and transformation tool |
| `mlir-translate` | MLIR to LLVM IR translator |

## Supported Platforms

| Platform | Architecture | File |
|----------|--------------|------|
| Linux | x86_64 | `mlir-linux-x64.tar.gz` |
| Linux | ARM64 | `mlir-linux-arm64.tar.gz` |
| macOS | x86_64 | `mlir-macos-x64.tar.gz` |
| macOS | ARM64 (Apple Silicon) | `mlir-macos-arm64.tar.gz` |
| Windows | x86_64 | `mlir-windows-x64.zip` |

## Usage

### GitHub Actions

```yaml
- name: Download MLIR Tools
  run: |
    curl -fsSL https://github.com/star-ga/mlir-tools/releases/download/llvmorg-18.1.8/mlir-linux-x64.tar.gz | tar xz
    echo "$PWD/mlir-linux-x64/bin" >> $GITHUB_PATH

- name: Use MLIR
  run: |
    mlir-opt --version
    mlir-translate --version
```

### macOS (Apple Silicon)

```bash
curl -fsSL https://github.com/star-ga/mlir-tools/releases/download/llvmorg-18.1.8/mlir-macos-arm64.tar.gz | tar xz
export PATH="$PWD/mlir-macos-arm64/bin:$PATH"
```

### Windows (PowerShell)

```powershell
Invoke-WebRequest -Uri "https://github.com/star-ga/mlir-tools/releases/download/llvmorg-18.1.8/mlir-windows-x64.zip" -OutFile mlir.zip
Expand-Archive mlir.zip -DestinationPath .
$env:PATH = "$PWD\mlir-windows-x64\bin;$env:PATH"
```

## Building

Releases are built automatically via GitHub Actions. To trigger a new build:

1. Go to **Actions** → **Build MLIR Tools**
2. Click **Run workflow**
3. Enter LLVM version tag (e.g., `llvmorg-18.1.8`)
4. Wait for all platforms to complete (~2-4 hours)

The release is created automatically when all builds succeed.

## Version

Current release is built from **LLVM 18.1.8**.

See [LLVM releases](https://github.com/llvm/llvm-project/releases) for available versions.

## License

The MLIR tools are part of the LLVM Project and are licensed under the **Apache License v2.0 with LLVM Exceptions**.

See [LICENSE](LICENSE) for details.

## Links

- [MLIR Documentation](https://mlir.llvm.org/)
- [LLVM Project](https://llvm.org/)
- [LLVM GitHub](https://github.com/llvm/llvm-project)
