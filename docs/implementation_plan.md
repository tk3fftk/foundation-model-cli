# Implementation Plan - OpenAI API互換エンドポイント

## 目的
- `fm` に OpenAI API 互換のエンドポイント起動オプションを追加する。
- 既存の単発CLI応答モードは維持する。

## 最小変更方針
1. `main.swift` に `--openai-compatible-api-endpoint`（short: `-o`）を追加。
   - 値あり: `host:port` で起動
   - 値なし: `localhost` の空きポートを `4000` から探索して起動
2. このオプション指定時のみ簡易HTTPサーバーを起動。
3. 互換対象は最小限として以下を提供:
   - `GET /v1/models`
   - `POST /v1/chat/completions`（`stream: true` は未対応として明示エラー）
4. 既存生成ロジックを関数化して通常CLIとAPIモードで共用。
5. `README.md` に利用例を追加。

## 検証計画
- 既存の `swift build` / `swift test` を実行して現状把握。
- 変更後に再度 `swift build` / `swift test` を試行（環境依存失敗は記録）。
- macOS環境での手動確認想定:
  - `fm --openai-compatible-api-endpoint 127.0.0.1:4000`
  - `curl` で `/v1/models` と `/v1/chat/completions` を確認。

# Implementation Plan - Foundation Model CLI

This plan outlines the steps to create a Command Line Interface (CLI) that utilizes Apple's `SystemLanguageModel` (part of the Foundation Models / Apple Intelligence framework) to generate text based on user input.

## User Review Required

> [!IMPORTANT]
> **Prerequisites**: This tool relies on the `FoundationModels` framework (or equivalent Apple Intelligence API) which is available on **macOS 15+ (Sequoia)** with **Xcode 16+**.
> The API name `SystemLanguageModel` is based on recent developer documentation for Apple Intelligence. If this framework is not found, we may need to fall back to `CoreML` or verify the exact framework name in your environment.

## Proposed Changes

### Project Structure
We will create a specific Swift Package Executable.

#### [NEW] Package.swift
- Define the package name `foundation-model-cli`.
- Add `swift-argument-parser` as a dependency.
- Define the executable target, product name: `fm`.

#### [NEW] Sources/main.swift
- Import `FoundationModels` (and `ArgumentParser`).
- Define the `FoundationModelCLI` struct implementing `ParsableCommand`.
- **Arguments**:
  - `prompt`: The input text (optional, if empty read from stdin).
- **Options**:
  - `--system-prompt`, `-s`: Custom instructions for the model (default: empty).
  - `--temperature`, `-t`: Controls randomness (0.0 to 1.0). Lower values are more deterministic. (default: 0.0)
  - `--sampling`, `-m`: Sampling strategy. Values: `greedy` (deterministic), `sampling` (randomized). (default: `greedy`)
  - `--debug`: Enable verbose logging.
  - `--version`: Show specific version.
- **Logic**:
  - Initialize `SystemLanguageModel.default`.
  - Create a session with the system prompt (`instructions`).
  - Generate response for the input prompt.
  - Print the result to stdout.

## CI (GitHub Actions)
- Add `.github/workflows/swift-ci.yml`.
- Pin `actions/checkout` to commit `de0fac2e4500dabe0009e67214ff5f5447ce83dd` (`v6.0.2`).
- Run on `push` to `main` and `pull_request`.
- Use `macos-26` runner, install `swiftlint`, then run:
  - `swiftlint lint`
  - `swift build -c release`

## Verification Plan

### Automated Tests
- Since this relies on OS-level AI models, unit tests for the model generation might be flaky or slow. We will focus on manual verification.
- We can add a simple unit test for Argument Parsing.

### Build Release Binary
1.  **Build the project**:
    ```bash
    swift build -c release
    ```
2.  **Run binary directly**:
    ```bash
    .build/release/fm "Explain quantum physics."
    ```

### Manual Verification
1.  **Run with argument**:
    ```bash
    swift run fm "Explain quantum physics in one sentence."
    ```
3.  **Run with system prompt**:
    ```bash
    swift run fm --system-prompt "You are a cat." "Hello"
    # Expected output: "Meow" or similar cat-like response.
    ```
4.  **Test Temperature**:
    ```bash
    # High temperature (creative)
    .build/release/fm -t 1.0 "Write a poem about code."
    # Low temperature (deterministic)
    .build/release/fm -t 0.0 "Write a poem about code."
    ```
5.  **Test Sampling**:
    ```bash
    # Greedy (deterministic)
    .build/release/fm -m greedy "Explain Swift."
    # Sampling (varied)
    .build/release/fm -m sampling "Explain Swift."
    ```
6.  **Run with standard input**:
    ```bash
    echo "What is the capital of France?" | swift run fm
    ```
