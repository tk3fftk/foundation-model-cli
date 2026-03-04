# Implementation Plan - Foundation Model CLI

This plan outlines the steps to create a Command Line Interface (CLI) that utilizes Apple's `SystemLanguageModel` (part of the Foundation Models / Apple Intelligence framework) to generate text based on user input.

## Hotfix Plan (OpenAI API SIGTRAP)

1. **Reproduce**: Confirm `fm -o` exits immediately with SIGTRAP because `dispatchMain()` runs off the main thread.
2. **Fix**: Start the listener on the main queue, execute on `@MainActor`, and block on the main thread using `RunLoop.main.run()` so the process stays alive until SIGTERM/Ctrl+C without trapping.
3. **Verify**: Run `swift test` (port search tests), `swift build -c release`, and launch the CLI; ensure the OpenAI API mode keeps running until SIGTERM / Ctrl+C. On environments without Network framework support, expect the explicit error message.

## Incremental Plan (OpenAI API Access Log)

1. Add a small access-log formatter helper to keep logging output consistent.
2. Print one access log line for each accepted HTTP request in OpenAI API mode.
3. Add a focused unit test for the formatter and run `swift test`.

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
  - `--openai-api`, `-o`: OpenAI API互換エンドポイントを起動。
  - `--openai-api-port`, `-p`: OpenAI API互換エンドポイントのポート番号（未指定時は`localhost:4000`から空きポートを動的選択）。
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

## Lint Hotfix Plan (run 22658023020)
- Rename `ReadLine()` to lowerCamelCase (`readStdin()`).
- Split overlong ternary expression for `samplingMode`.
- Remove trailing whitespaces in `main.swift`.
- Remove trailing commas in `Package.swift`.

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
