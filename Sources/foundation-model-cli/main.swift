import Foundation
import ArgumentParser
import FoundationModels

@main
@available(macOS 26.0, *)
struct FoundationModelCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fm",
        abstract: "A CLI tool to interact with Apple's Foundation Models.",
        version: "0.1.0"
    )

    @Argument(help: "The input prompt for the model. If not provided, reads from standard input.")
    var prompt: String?

    @Option(name: [.customShort("s"), .customLong("system-prompt")], help: "Custom instructions for the model.")
    var systemPrompt: String = ""

    @Option(name: [.customShort("t"), .customLong("temperature")], help: "Controls randomness (0.0 to 1.0).")
    var temperature: Double = 0.0

    @Option(name: [.customShort("m"), .customLong("sampling")], help: "Sampling strategy: greedy or sampling.")
    var sampling: SamplingStrategy = .greedy

    @Flag(name: .long, help: "Enable verbose logging.")
    var debug: Bool = false

    mutating func run() async throws {
        var localStandardError = StandardError()
        let inputPrompt: String
        if let promptArgument = prompt {
            inputPrompt = promptArgument
        } else {
            // Read from stdin if no argument provided
            guard let stdinData = readStdin() else {
                print("Error: No input provided via argument or stdin.", to: &localStandardError)
                throw ExitCode.validationFailure
            }
            inputPrompt = stdinData
        }

        if debug {
            print("Debug: System Prompt: \(systemPrompt)")
            print("Debug: User Prompt: \(inputPrompt)")
            print("Debug: Temperature: \(temperature)")
            print("Debug: Sampling: \(sampling)")
            print("Debug: Initializing SystemLanguageModel...")
        }

        do {
            let model = SystemLanguageModel.default

            if debug {
                print("Debug: Creating session...")
            }

            let session = LanguageModelSession(model: model, instructions: systemPrompt)

            if debug {
                print("Debug: Generating response...")
            }

            // Map CLI sampling argument to API SamplingMode
            // Note: Using a top-p threshold of 1.0 for 'sampling' to mimic standard sampling behavior.
            let samplingMode: GenerationOptions.SamplingMode = sampling == .greedy
                ? .greedy
                : .random(probabilityThreshold: 1.0, seed: nil)

            let options = GenerationOptions(
                sampling: samplingMode,
                temperature: temperature
            )

            let response = try await session.respond(to: inputPrompt, options: options)
            print(response.content)

        } catch {
            print("Error: \(error.localizedDescription)", to: &localStandardError)
            if debug {
                print("Debug Detailed Error: \(error)")
            }
            throw ExitCode.failure
        }
    }

    // Helper to read all stdin
    private func readStdin() -> String? {
        var input = ""
        while let line = readLine(strippingNewline: false) {
            input += line
        }
        return input.isEmpty ? nil : input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SamplingStrategy: String, ExpressibleByArgument {
    case greedy
    case sampling
}

struct StandardError: TextOutputStream {
    func write(_ string: String) {
        try? FileHandle.standardError.write(contentsOf: Data(string.utf8))
    }
}
