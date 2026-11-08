// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/

import Foundation

#if !canImport(FoundationModels)

public struct SystemLanguageModel: Sendable {
    public struct Guardrails: Sendable {
        public static let permissiveContentTransformations = Guardrails()
        public init() {}
    }
    public static let `default` = SystemLanguageModel()
    public var isAvailable: Bool { false }
    public init(guardrails: Guardrails = Guardrails()) {}
}

public struct Prompt: Sendable {
    public var text: String
    public init(_ text: String) {
        self.text = text
    }
}

public struct GenerationOptions: Sendable {
    public enum SamplingMode: Sendable {
        case standard
    }
    public var sampling: SamplingMode?
    public var temperature: Double?
    public var maximumResponseTokens: Int?
    public init(
        sampling: SamplingMode? = nil,
        temperature: Double? = nil,
        maximumResponseTokens: Int? = nil
    ) {
        self.sampling = sampling
        self.temperature = temperature
        self.maximumResponseTokens = maximumResponseTokens
    }
}

public struct Transcript: Sendable {
    public struct Entry: Sendable {
        public var text: String = ""
        public init() {}
    }
}

public final class LanguageModelSession: @unchecked Sendable {
    public enum GenerationError: Error {
        case exceededContextWindowSize
        case rateLimited
        case concurrentRequests
        case guardrailViolation
        case unsupportedLanguageOrLocale
        case unsupportedGuide
        case decodingFailure
        case assetsUnavailable
        case refusal
    }

    public enum ToolCallError: Error {}

    public struct Response<Content>: Sendable {
        public var content: Content
        public var transcriptEntries: ArraySlice<Transcript.Entry> { [] }
        public init(content: Content) {
            self.content = content
        }
    }

    public struct ResponseStream<Content>: AsyncSequence, Sendable {
        public typealias Element = Snapshot
        public struct Snapshot: Sendable {
            public var content: String = ""
            public init() {}
        }
        public struct AsyncIterator: AsyncIteratorProtocol {
            public mutating func next() async throws -> Snapshot? { nil }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator() }
        public init() {}
    }

    public init(model: SystemLanguageModel = .default, instructions: String = "") {}

    public func respond(
        to prompt: Prompt,
        options: GenerationOptions = .init()
    ) async throws -> Response<String> {
        return Response(content: "")
    }

    public func streamResponse(
        to prompt: Prompt,
        options: GenerationOptions = .init()
    ) -> ResponseStream<String> {
        return ResponseStream()
    }
}

#endif
