import Foundation

public struct SpeakerIdentityProfile: Codable, Equatable, Sendable {
    public let userId: String
    public let displayName: String
    public let embedding: [Double]

    public init(userId: String, displayName: String, embedding: [Double]) {
        self.userId = userId
        self.displayName = displayName
        self.embedding = embedding
    }
}

public struct SpeakerIdentityResult: Decodable, Equatable, Sendable {
    public let userId: String?
    public let displayName: String?
    public let score: Double?
    public let model: String
}

public struct SpeakerIdentityHealth: Decodable, Equatable, Sendable {
    public let ok: Bool
    public let service: String
    public let model: String
}

public enum SpeakerIdentityError: Error, Equatable {
    case invalidResponse
    case httpStatus(Int)
}

public final class SpeakerIdentityClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func health() async throws -> SpeakerIdentityHealth {
        let (data, response) = try await session.data(from: baseURL.appending(path: "health"))
        try Self.validate(response)
        return try decoder.decode(SpeakerIdentityHealth.self, from: data)
    }

    public func enroll(samples: [VoiceCaptureAudio]) async throws -> SpeakerIdentityProfile {
        let request = EnrollRequest(samples: samples.map(AudioSample.init))
        let response: EnrollResponse = try await post("v1/enroll", body: request)
        return SpeakerIdentityProfile(
            userId: "owner",
            displayName: "Owner",
            embedding: response.embedding
        )
    }

    public func identify(
        sample: VoiceCaptureAudio,
        profiles: [SpeakerIdentityProfile],
        threshold: Double? = nil
    ) async throws -> SpeakerIdentityResult {
        let request = IdentifyRequest(
            sample: AudioSample(sample),
            profiles: profiles,
            threshold: threshold
        )
        return try await post("v1/identify", body: request)
    }

    private func post<RequestBody: Encodable, ResponseBody: Decodable>(
        _ path: String,
        body: RequestBody
    ) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)
        return try decoder.decode(ResponseBody.self, from: data)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw SpeakerIdentityError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SpeakerIdentityError.httpStatus(http.statusCode)
        }
    }

    private struct AudioSample: Encodable {
        let audioBase64: String
        let mimeType: String
        let durationMs: Int?

        init(_ audio: VoiceCaptureAudio) {
            self.audioBase64 = audio.wavData().base64EncodedString()
            self.mimeType = "audio/wav"
            self.durationMs = Int((audio.durationSeconds * 1000).rounded())
        }
    }

    private struct EnrollRequest: Encodable {
        let samples: [AudioSample]
    }

    private struct EnrollResponse: Decodable {
        let embedding: [Double]
        let sampleCount: Int
        let model: String
    }

    private struct IdentifyRequest: Encodable {
        let sample: AudioSample
        let profiles: [SpeakerIdentityProfile]
        let threshold: Double?
    }
}

public enum SpeakerIdentityProfileStore {
    public static var defaultURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Sidekick", isDirectory: true)
            .appendingPathComponent("VoiceProfile.json")
    }

    public static func load(from url: URL = defaultURL) -> SpeakerIdentityProfile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SpeakerIdentityProfile.self, from: data)
    }

    public static func save(_ profile: SpeakerIdentityProfile, to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(profile)
        try data.write(to: url, options: [.atomic])
    }

    public static func delete(from url: URL = defaultURL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
