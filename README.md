# MLIR Tools

Pre-built MLIR tools for MIND compiler builds.

## Tools Included

- `mlir-opt` - MLIR optimizer
- `mlir-translate` - MLIR to LLVM IR translator

## Platforms

| Platform | Archive |
|----------|---------|
| Linux x64 | `mlir-linux-x64.tar.gz` |
| Linux ARM64 | `mlir-linux-arm64.tar.gz` |
| Windows x64 | `mlir-windows-x64.zip` |
| macOS x64 | `mlir-macos-x64.tar.gz` |
| macOS ARM64 | `mlir-macos-arm64.tar.gz` |

## Usage in CI

```yaml
- name: Download MLIR Tools
  run: |
    curl -fsSL https://github.com/star-ga/mlir-tools/releases/download/llvmorg-18.1.8/mlir-linux-x64.tar.gz | tar xz
    echo "$PWD/mlir-linux-x64/bin" >> $GITHUB_PATH

- name: Build with MIND
  run: mindc build --release
```

## Building

Trigger the workflow manually from Actions tab:

1. Go to Actions → Build MLIR Tools
2. Click "Run workflow"
3. Enter LLVM version (default: `llvmorg-18.1.8`)
4. Wait ~2-4 hours for all platforms to build
5. Release is created automatically with all binaries

## License

LLVM/MLIR tools are licensed under Apache 2.0 with LLVM Exceptions.
