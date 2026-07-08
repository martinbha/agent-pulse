import Foundation

@testable import AgentPulseCore

enum CodexUsageFixtures {
    // MARK: - JSON-RPC framing

    static func framedLine() -> String? {
        let pipe = Pipe()
        try? writeJSONLine(["id": 7], to: pipe.fileHandleForWriting)
        try? pipe.fileHandleForWriting.close()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Response reading

    static func matchedResponseValue() async -> String? {
        let lines = [
            "not-json at all",
            "",
            #"{"jsonrpc":"2.0","method":"sessionConfigured","params":{}}"#,
            #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#,
            #"{"jsonrpc":"2.0","id":2,"result":{"value":"matched"}}"#,
        ]

        guard let payload = try? await readJSONRPCResponse(withID: 2, from: stream(of: lines)) else {
            return nil
        }
        return (payload["result"] as? [String: Any])?["value"] as? String
    }

    static func matchesStringIDs() async -> Bool {
        let lines = [#"{"jsonrpc":"2.0","id":"2","result":{"ok":true}}"#]
        let payload = try? await readJSONRPCResponse(withID: 2, from: stream(of: lines))
        return payload != nil
    }

    static func errorPayloadMessage() async -> String? {
        let lines = [#"{"jsonrpc":"2.0","id":3,"error":{"code":-32000,"message":"not logged in"}}"#]

        do {
            _ = try await readJSONRPCResponse(withID: 3, from: stream(of: lines))
            return nil
        } catch let error as ProcessRunnerError {
            guard case .invalidResponse(let message) = error else {
                return nil
            }
            return message
        } catch {
            return nil
        }
    }

    static func closedStreamMessage() async -> String? {
        do {
            _ = try await readJSONRPCResponse(withID: 9, from: stream(of: [#"{"id":1,"result":{}}"#]))
            return nil
        } catch let error as ProcessRunnerError {
            guard case .invalidResponse(let message) = error else {
                return nil
            }
            return message
        } catch {
            return nil
        }
    }

    static func timeoutOutcome() async -> (timedOut: Bool, terminatorCalls: Int) {
        let holder = ContinuationHolder()
        let counter = CallCounter()
        let never = AsyncStream<String> { continuation in
            holder.store(continuation)
        }

        do {
            _ = try await readJSONRPCResponse(
                withID: 1,
                from: never,
                timeout: .milliseconds(50),
                onTimeout: { _ = counter.increment() }
            )
            holder.finish()
            return (false, counter.count)
        } catch let error as ProcessRunnerError {
            holder.finish()
            guard case .timedOut = error else {
                return (false, counter.count)
            }
            return (true, counter.count)
        } catch {
            holder.finish()
            return (false, counter.count)
        }
    }

    // MARK: - Window parsing

    static func parsedFullWindow() -> (used: Double?, resetEpoch: Double?) {
        let window = CodexUsageProbe().parseWindow([
            "usedPercent": 41.5,
            "resetsAt": 1_767_225_600,
        ])
        return (window?.usedPercent, window?.resetsAt?.timeIntervalSince1970)
    }

    static func windowWithoutUsedPercentIsNil() -> Bool {
        CodexUsageProbe().parseWindow(["resetsAt": 1_767_225_600]) == nil
    }

    static func windowWithStringNumbersParses() -> (used: Double?, resetEpoch: Double?) {
        let window = CodexUsageProbe().parseWindow([
            "usedPercent": "41.5",
            "resetsAt": "1767225600",
        ])
        return (window?.usedPercent, window?.resetsAt?.timeIntervalSince1970)
    }

    static func numericCoercions() -> [Double?] {
        let probe = CodexUsageProbe()
        return [
            probe.numericValue(41.5),
            probe.numericValue(42),
            probe.numericValue("43.5"),
            probe.numericValue("not-a-number"),
            probe.numericValue(nil),
        ]
    }

    // MARK: - Helpers

    private static func stream(of lines: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            for line in lines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }

    final class ContinuationHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<String>.Continuation?

        func store(_ continuation: AsyncStream<String>.Continuation) {
            lock.lock()
            defer { lock.unlock() }
            self.continuation = continuation
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            continuation?.finish()
            continuation = nil
        }
    }
}
