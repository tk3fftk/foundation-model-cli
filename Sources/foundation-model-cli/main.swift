import Foundation
import ArgumentParser
import Dispatch
#if canImport(Network)
import Network
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct FoundationModelCLIEntryPoint {
    static func main() async {
        if #available(macOS 26.0, *) {
            await FoundationModelCLI.main()
        } else {
            var stderr = StandardError()
            let version = ProcessInfo.processInfo.operatingSystemVersion
            let versionString = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
            print("Error: macOS 26.0 (Tahoe) or later is required to use Foundation Models.", to: &stderr)
            print("Current macOS version: \(versionString)", to: &stderr)
            exit(1)
        }
    }
}

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

    @Flag(
        name: [.customShort("o"), .customLong("openai-api")],
        help: "Start an OpenAI-compatible API endpoint on localhost."
    )
    var openAIAPI: Bool = false

    @Option(
        name: [.customLong("openai-api-port"), .customShort("p")],
        help: "Port for the OpenAI-compatible API endpoint."
    )
    var openAIAPIPort: Int?

    mutating func run() async throws {
        var localStandardError = StandardError()
        if openAIAPI {
            let serverPort = try findAvailablePort(preferredPort: openAIAPIPort, startPort: 4000)
            let server = OpenAICompatibleServer(
                port: serverPort,
                defaultSystemPrompt: systemPrompt,
                debug: debug
            )
            try await server.start()
            return
        }

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
            let responseText = try await generateResponse(
                inputPrompt: inputPrompt,
                systemPrompt: systemPrompt,
                temperature: temperature,
                sampling: sampling,
                debug: debug
            )
            print(responseText)
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

enum FoundationModelCLIError: LocalizedError {
    case foundationModelsUnavailable
    case networkFrameworkUnavailable
    case noOpenPort(startPort: Int)
    case invalidPort(Int)
    case portUnavailable(Int)

    var errorDescription: String? {
        switch self {
        case .foundationModelsUnavailable:
            return "FoundationModels framework is not available in this environment."
        case .networkFrameworkUnavailable:
            return "Network framework is not available in this environment."
        case .noOpenPort(let startPort):
            return "No open localhost port found from \(startPort)."
        case .invalidPort(let port):
            return "Invalid port: \(port). Use a value between 1 and 65535."
        case .portUnavailable(let port):
            return "Port \(port) is already in use on localhost."
        }
    }
}

func findAvailablePort(preferredPort: Int?, startPort: Int) throws -> Int {
    if let preferredPort {
        guard (1...65535).contains(preferredPort) else {
            throw FoundationModelCLIError.invalidPort(preferredPort)
        }
        if isPortAvailable(preferredPort) {
            return preferredPort
        }
        throw FoundationModelCLIError.portUnavailable(preferredPort)
    }

    for port in startPort...65535 where isPortAvailable(port) {
        return port
    }
    throw FoundationModelCLIError.noOpenPort(startPort: startPort)
}

@available(macOS 26.0, *)
func generateResponse(
    inputPrompt: String,
    systemPrompt: String,
    temperature: Double,
    sampling: SamplingStrategy,
    debug: Bool
) async throws -> String {
    #if canImport(FoundationModels)
    let model = SystemLanguageModel.default

    if debug {
        print("Debug: Creating session...")
    }

    let session = LanguageModelSession(model: model, instructions: systemPrompt)

    if debug {
        print("Debug: Generating response...")
    }

    let samplingMode: GenerationOptions.SamplingMode = sampling == .greedy
        ? .greedy
        : .random(probabilityThreshold: 1.0, seed: nil)

    let options = GenerationOptions(
        sampling: samplingMode,
        temperature: temperature
    )

    let response = try await session.respond(to: inputPrompt, options: options)
    return response.content
    #else
    throw FoundationModelCLIError.foundationModelsUnavailable
    #endif
}

func isPortAvailable(_ port: Int) -> Bool {
    #if canImport(Darwin)
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    #else
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    #endif
    guard fd >= 0 else { return false }
    defer { _ = close(fd) }

    var address = sockaddr_in()
#if canImport(Darwin)
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
#endif
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(UInt16(port)).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }

    return bindResult == 0
}

func makeOpenAIAccessLog(remoteEndpoint: String, requestLine: String, date: Date = Date()) -> String {
    let timestamp = date.formatted(.iso8601)
    return "[\(timestamp)] \(remoteEndpoint) \"\(requestLine)\""
}

#if canImport(Network)
@available(macOS 26.0, *)
struct OpenAICompatibleServer {
    private let maxHTTPRequestSizeBytes = 1_048_576
    let port: Int
    let defaultSystemPrompt: String
    let debug: Bool

    func start() async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw FoundationModelCLIError.invalidPort(port)
        }

        let listener = try NWListener(using: .tcp, on: nwPort)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(
                minimumIncompleteLength: 1,
                maximumLength: maxHTTPRequestSizeBytes
            ) { data, _, _, receiveError in
                guard receiveError == nil else {
                    connection.cancel()
                    return
                }
                Task {
                    await handle(connection: connection, data: data)
                }
            }
        }
        listener.start(queue: .global())

        print("OpenAI-compatible endpoint listening on http://127.0.0.1:\(port)/v1/chat/completions")

        let signals = AsyncStream<Void> { continuation in
            signal(SIGINT, SIG_IGN)
            signal(SIGTERM, SIG_IGN)
            let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            sigintSource.setEventHandler { continuation.finish() }
            sigtermSource.setEventHandler { continuation.finish() }
            sigintSource.resume()
            sigtermSource.resume()
            continuation.onTermination = { _ in
                sigintSource.cancel()
                sigtermSource.cancel()
            }
        }
        for await _ in signals {}

        withExtendedLifetime(listener) {}
    }

    private func handle(connection: NWConnection, data: Data?) async {
        guard
            let data,
            let request = String(data: data, encoding: .utf8),
            let requestLine = request.components(separatedBy: "\r\n").first
        else {
            send(connection: connection, statusCode: 400, body: #"{"error":"Invalid request"}"#)
            return
        }

        let parts = requestLine.split(separator: " ")
        let resolvedEndpoint = connection.currentPath?.remoteEndpoint ?? connection.endpoint
        let remoteEndpoint: String
        switch resolvedEndpoint {
        case .hostPort(let host, let port):
            remoteEndpoint = "\(host):\(port.rawValue)"
        case .service(let name, let type, let domain, _):
            remoteEndpoint = "\(name).\(type).\(domain)"
        case .unix(let path):
            remoteEndpoint = path
        default:
            remoteEndpoint = "unknown:\(resolvedEndpoint)"
        }
        print(makeOpenAIAccessLog(remoteEndpoint: remoteEndpoint, requestLine: requestLine))
        guard parts.count >= 2, parts[0] == "POST", parts[1] == "/v1/chat/completions" else {
            send(connection: connection, statusCode: 404, body: #"{"error":"Not found"}"#)
            return
        }

        guard let bodyRange = request.range(of: "\r\n\r\n") else {
            send(connection: connection, statusCode: 400, body: #"{"error":"Missing request body"}"#)
            return
        }

        let body = String(request[bodyRange.upperBound...])
        guard let bodyData = body.data(using: .utf8) else {
            send(connection: connection, statusCode: 400, body: #"{"error":"Invalid body encoding"}"#)
            return
        }

        do {
            let completionRequest = try JSONDecoder().decode(OpenAIChatCompletionsRequest.self, from: bodyData)
            if completionRequest.stream == true {
                send(connection: connection, statusCode: 400, body: #"{"error":"stream=true is not supported"}"#)
                return
            }

            let systemPrompt = completionRequest.messages.first { $0.role == "system" }?.content ?? defaultSystemPrompt
            let userPrompt = completionRequest.messages
                .filter { $0.role == "user" }
                .map(\.content)
                .joined(separator: "\n")
            guard !userPrompt.isEmpty else {
                send(connection: connection, statusCode: 400, body: #"{"error":"No user message found"}"#)
                return
            }

            let text = try await generateResponse(
                inputPrompt: userPrompt,
                systemPrompt: systemPrompt,
                temperature: completionRequest.temperature ?? 0.0,
                sampling: (completionRequest.temperature ?? 0.0) <= 0 ? .greedy : .sampling,
                debug: debug
            )

            let response = OpenAIChatCompletionsResponse(
                id: "chatcmpl-\(UUID().uuidString)",
                created: Int(Date().timeIntervalSince1970),
                model: completionRequest.model ?? "foundation-model",
                choices: [
                    .init(
                        index: 0,
                        message: .init(role: "assistant", content: text),
                        finishReason: "stop"
                    )
                ]
            )
            let responseData = try JSONEncoder().encode(response)
            if let responseBody = String(data: responseData, encoding: .utf8) {
                send(connection: connection, statusCode: 200, body: responseBody)
            } else {
                send(connection: connection, statusCode: 500, body: #"{"error":"Failed to encode response"}"#)
            }
        } catch {
            send(
                connection: connection,
                statusCode: 500,
                body: encodeErrorBody(error.localizedDescription)
            )
        }
    }

    private func send(connection: NWConnection, statusCode: Int, body: String) {
        let statusText: String
        switch statusCode {
        case 200:
            statusText = "OK"
        case 400:
            statusText = "Bad Request"
        case 404:
            statusText = "Not Found"
        case 500:
            statusText = "Internal Server Error"
        default:
            statusText = "Error"
        }
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        let data = Data(response.utf8)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func encodeErrorBody(_ message: String) -> String {
        let payload = OpenAIErrorResponse(error: message)
        guard
            let data = try? JSONEncoder().encode(payload),
            let text = String(data: data, encoding: .utf8)
        else {
            return #"{"error":"Internal error"}"#
        }
        return text
    }
}
#else
struct OpenAICompatibleServer {
    let port: Int
    let defaultSystemPrompt: String
    let debug: Bool

    func start() async throws {
        throw FoundationModelCLIError.networkFrameworkUnavailable
    }
}
#endif

struct OpenAIChatCompletionsRequest: Decodable {
    let model: String?
    let messages: [OpenAIChatMessage]
    let temperature: Double?
    let stream: Bool?
}

struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatCompletionsResponse: Encodable {
    let id: String
    let object: String = "chat.completion"
    let created: Int
    let model: String
    let choices: [OpenAIChatChoice]
}

struct OpenAIChatChoice: Encodable {
    let index: Int
    let message: OpenAIChatMessage
    let finishReason: String

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

struct OpenAIErrorResponse: Encodable {
    let error: String
}

struct StandardError: TextOutputStream {
    func write(_ string: String) {
        try? FileHandle.standardError.write(contentsOf: Data(string.utf8))
    }
}
