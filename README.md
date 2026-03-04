# Foundation Model CLI (`fm`)

A command-line interface for Apple's Foundation Models (Apple Intelligence), allowing you to generate text using on-device Large Language Models on macOS.

## Requirements

- **macOS 15+ (Sequoia)** or newer (specifically versions supporting Apple Intelligence, e.g., macOS 26.0).
- **Apple Silicon** Mac with Apple Intelligence enabled.
- **Xcode 16+** (for building).

## Installation

### From Source

1.  Clone the repository:
    ```bash
    git clone https://github.com/tk3fftk/foundation-model-cli.git
    cd foundation-model-cli
    ```

2.  Build the project:
    ```bash
    swift build -c release
    ```

3.  The binary will be located at `.build/release/fm`. You can move it to your path:
    ```bash
    cp .build/release/fm /usr/local/bin/fm
    ```

## Usage

The CLI tool `fm` accepts input via arguments or standard input.

### Basic Generation

```bash
fm "Why is the sky blue?"
```

### Options

| Option | Short | Description | Default |
| :--- | :--- | :--- | :--- |
| `--system-prompt` | `-s` | Custom instructions for the model. | (empty) |
| `--temperature` | `-t` | Controls randomness (0.0 to 1.0). | `0.0` (Deterministic) |
| `--sampling` | `-m` | Sampling strategy: `greedy` or `sampling`. | `greedy` |
| `--openai-api` | `-o` | OpenAI API互換エンドポイントを起動。`--openai-api-port`未指定時は`localhost:4000`から空きポートを自動選択。 | `false` |
| `--openai-api-port` | `-p` | OpenAI API互換エンドポイントのポート番号。 | (auto) |
| `--debug` | | Enable verbose logging. | `false` |
| `--version` | | Show the version. | |

### Examples

**Standard Input:**
```bash
echo "Explain quantum computing" | fm
```

**System Prompt:**
```bash
fm -s "You are a poet." "Write about coding."
```

**Creative Generation (High Temperature):**
```bash
fm -t 1.0 -m sampling "Brainstorm catchy names for a coffee shop."
```

**Deterministic Output:**
```bash
fm -t 0.0 -m greedy "What is the capital of France?"
```

**OpenAI API互換エンドポイント起動 (ポート自動選択):**
```bash
fm -o
# 例: OpenAI-compatible endpoint listening on http://127.0.0.1:4000/v1/chat/completions
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
