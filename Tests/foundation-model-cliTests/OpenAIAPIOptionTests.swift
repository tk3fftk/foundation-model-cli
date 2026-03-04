import XCTest
@testable import foundation_model_cli

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class OpenAIAPIOptionTests: XCTestCase {
    func testFindAvailablePortSkipsOccupiedPort() throws {
        let socketFD = makeBoundSocket(port: 4000)
        defer { _ = close(socketFD) }

        let resolvedPort = try findAvailablePort(preferredPort: nil, startPort: 4000)
        XCTAssertNotEqual(resolvedPort, 4000)
        XCTAssertGreaterThanOrEqual(resolvedPort, 4001)
    }

    func testFindAvailablePortRejectsInvalidPreferredPort() {
        XCTAssertThrowsError(try findAvailablePort(preferredPort: 70000, startPort: 4000))
    }

    private func makeBoundSocket(port: Int) -> Int32 {
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        XCTAssertGreaterThanOrEqual(fd, 0)

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
        XCTAssertEqual(bindResult, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        return fd
    }
}
