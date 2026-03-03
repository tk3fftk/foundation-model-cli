import Foundation
import ArgumentParser
import FoundationModels
#if canImport(Network)
import Network
#endif

@main
@available(macOS 26.0, *)
struct FoundationModelCLI: AsyncParsableCommand {
    private static let maxRequestBodySize = 1_048_576
    private static let maxHTTPRequestSize = maxRequestBodySize + 16_384
    
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
    
    @Option(name: .customLong("openai-compatible-api-endpoint"), help: "Launch OpenAI-compatible API endpoint at host:port (example: 127.0.0.1:4000).")
    var openAICompatibleAPIEndpoint: String?

    mutating func run() async throws {
        var localStandardError = StandardError()
        
        if let endpoint = openAICompatibleAPIEndpoint {
            do {
                try runOpenAICompatibleAPIServer(endpoint: endpoint)
            } catch {
                print("Error: \(error.localizedDescription)", to: &localStandardError)
                throw ExitCode.failure
            }
            return
        }
        
        let inputPrompt: String
        if let promptArgument = prompt {
            inputPrompt = promptArgument
        } else {
            // Read from stdin if no argument provided
            guard let stdinData = ReadLine() else {
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
            let output = try await generateModelResponse(inputPrompt: inputPrompt, systemPrompt: systemPrompt, temperature: temperature, sampling: sampling)
            print(output)
        } catch {
            print("Error: \(error.localizedDescription)", to: &localStandardError)
            if debug {
                print("Debug Detailed Error: \(error)")
            }
            throw ExitCode.failure
        }
    }

    // Helper to read all stdin
    private func ReadLine() -> String? {
        var input = ""
        while let line = readLine(strippingNewline: false) {
            input += line
        }
        return input.isEmpty ? nil : input.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func generateModelResponse(inputPrompt: String, systemPrompt: String, temperature: Double, sampling: SamplingStrategy) async throws -> String {
        let model = SystemLanguageModel.default
        let session = LanguageModelSession(model: model, instructions: systemPrompt)
        let samplingMode: GenerationOptions.SamplingMode = sampling == .greedy ? .greedy : .random(probabilityThreshold: 1.0, seed: nil)
        let options = GenerationOptions(
            sampling: samplingMode,
            temperature: temperature
        )
        
        if debug {
            print("Debug: Creating session...")
            print("Debug: Generating response...")
        }
        
        let response = try await session.respond(to: inputPrompt, options: options)
        return response.content
    }
    
    #if canImport(Network)
    private func runOpenAICompatibleAPIServer(endpoint: String) throws {
        guard let (host, port) = parseHostAndPort(from: endpoint) else {
            throw ValidationError("Invalid --openai-compatible-api-endpoint value. Use host:port (example: 127.0.0.1:4000).")
        }
        
        let listener = try NWListener(using: .tcp, on: port)
        let queue = DispatchQueue(label: "fm.openai-compatible-api")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            self.handleOpenAICompatibleConnection(connection)
        }
        listener.start(queue: queue)
        print("OpenAI-compatible API endpoint started on all interfaces at port \(port.rawValue) (requested: \(host):\(port.rawValue))")
        dispatchMain()
    }
    
    private func parseHostAndPort(from endpoint: String) -> (String, NWEndpoint.Port)? {
        let values = endpoint.split(separator: ":", maxSplits: 1).map(String.init)
        guard values.count == 2, !values[0].isEmpty, let numericPort = UInt16(values[1]), let port = NWEndpoint.Port(rawValue: numericPort) else {
            return nil
        }
        return (values[0], port)
    }
    
    private func handleOpenAICompatibleConnection(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxHTTPRequestSize) { data, _, _, _ in
            guard let data else {
                connection.cancel()
                return
            }
            
            Task {
                let response = await self.makeOpenAICompatibleResponse(from: data)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
    
    private func makeOpenAICompatibleResponse(from data: Data) async -> Data {
        guard let request = String(data: data, encoding: .utf8),
              let requestParts = splitHTTPRequest(request) else {
            return httpResponse(statusCode: 400, statusText: "Bad Request", body: OpenAIErrorPayload(error: .init(message: "Malformed HTTP request.", type: "invalid_request_error")))
        }
        
        if let contentLength = requestParts.headers["content-length"], let bodySize = Int(contentLength), bodySize > Self.maxRequestBodySize {
            return httpResponse(statusCode: 413, statusText: "Payload Too Large", body: OpenAIErrorPayload(error: .init(message: "Request body is too large (max 1MB).", type: "invalid_request_error")))
        }
        
        let lineParts = requestParts.requestLine.split(separator: " ")
        guard lineParts.count >= 2 else {
            return httpResponse(statusCode: 400, statusText: "Bad Request", body: OpenAIErrorPayload(error: .init(message: "Malformed request line.", type: "invalid_request_error")))
        }
        
        let method = String(lineParts[0])
        let path = String(lineParts[1])
        
        if method == "GET", path == "/v1/models" {
            let payload = OpenAIModelListPayload(data: [.init(id: "foundation-model-cli", object: "model", ownedBy: "apple-foundation-models")])
            return httpResponse(statusCode: 200, statusText: "OK", body: payload)
        }
        
        guard method == "POST", path == "/v1/chat/completions" else {
            return httpResponse(statusCode: 404, statusText: "Not Found", body: OpenAIErrorPayload(error: .init(message: "Unsupported endpoint.", type: "invalid_request_error")))
        }
        
        guard let bodyData = requestParts.body.data(using: .utf8),
              let payload = try? JSONDecoder().decode(OpenAIChatCompletionRequest.self, from: bodyData) else {
            return httpResponse(statusCode: 400, statusText: "Bad Request", body: OpenAIErrorPayload(error: .init(message: "Invalid JSON body.", type: "invalid_request_error")))
        }
        
        if payload.stream == true {
            return httpResponse(statusCode: 400, statusText: "Bad Request", body: OpenAIErrorPayload(error: .init(message: "stream=true is not supported.", type: "invalid_request_error")))
        }
        
        guard let latestUserPrompt = payload.messages.last(where: { $0.role == "user" })?.content else {
            return httpResponse(statusCode: 400, statusText: "Bad Request", body: OpenAIErrorPayload(error: .init(message: "At least one user message is required.", type: "invalid_request_error")))
        }
        
        let mergedSystemPrompt = ([systemPrompt] + payload.messages.filter { $0.role == "system" }.map(\.content))
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        
        do {
            let output = try await generateModelResponse(
                inputPrompt: latestUserPrompt,
                systemPrompt: mergedSystemPrompt,
                temperature: payload.temperature ?? temperature,
                sampling: sampling
            )
            
            let completionPayload = OpenAIChatCompletionResponse(
                id: "chatcmpl-\(UUID().uuidString)",
                model: payload.model ?? "foundation-model-cli",
                choices: [
                    .init(
                        index: 0,
                        message: .init(role: "assistant", content: output),
                        finishReason: "stop"
                    )
                ],
                usage: .init(promptTokens: 0, completionTokens: 0, totalTokens: 0)
            )
            return httpResponse(statusCode: 200, statusText: "OK", body: completionPayload)
        } catch {
            return httpResponse(statusCode: 500, statusText: "Internal Server Error", body: OpenAIErrorPayload(error: .init(message: error.localizedDescription, type: "server_error")))
        }
    }
    
    private func splitHTTPRequest(_ request: String) -> (requestLine: String, headers: [String: String], body: String)? {
        let separator = "\r\n\r\n"
        guard let range = request.range(of: separator) else { return nil }
        let headerSection = request[..<range.lowerBound]
        let bodySection = request[range.upperBound...]
        let lines = headerSection.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard let firstHeaderLine = lines.first else {
            return nil
        }
        
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separatorIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        
        return (String(firstHeaderLine), headers, String(bodySection))
    }
    
    private func httpResponse<T: Encodable>(statusCode: Int, statusText: String, body: T) -> Data {
        let jsonData = (try? JSONEncoder().encode(body)) ?? Data("{\"error\":{\"message\":\"Encoding error.\",\"type\":\"server_error\"}}".utf8)
        var response = Data("HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: application/json\r\nContent-Length: \(jsonData.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(jsonData)
        return response
    }
    #endif
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

private struct OpenAIChatCompletionRequest: Decodable {
    let model: String?
    let messages: [OpenAIChatMessage]
    let temperature: Double?
    let stream: Bool?
}

private struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIChatCompletionResponse: Encodable {
    let id: String
    let object: String = "chat.completion"
    let created: Int = Int(Date().timeIntervalSince1970)
    let model: String
    let choices: [Choice]
    let usage: Usage
    
    struct Choice: Encodable {
        let index: Int
        let message: OpenAIChatMessage
        let finishReason: String
        
        enum CodingKeys: String, CodingKey {
            case index
            case message
            case finishReason = "finish_reason"
        }
    }
    
    struct Usage: Encodable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct OpenAIModelListPayload: Encodable {
    let object: String = "list"
    let data: [Item]
    
    struct Item: Encodable {
        let id: String
        let object: String
        let ownedBy: String
        
        enum CodingKeys: String, CodingKey {
            case id
            case object
            case ownedBy = "owned_by"
        }
    }
}

private struct OpenAIErrorPayload: Encodable {
    let error: ErrorBody
    
    struct ErrorBody: Encodable {
        let message: String
        let type: String
    }
}
