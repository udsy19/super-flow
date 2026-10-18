import CryptoKit
import FluidAudio
import Foundation
import SuperFlowCore

/// Where a catalog model lives on disk and what it is made of (local-models.md §5.2).
///
/// - A single file (`url` + `sha256`): `Models/<kind>/<file>`, downloaded as `<file>.partial` next to it.
/// - A FluidAudio Core ML set (`repository` + `revision`): the folder `Models/<kind>/<id>/` holding exactly the files
///   FluidAudio loads, staged in `<id>.partial/` and renamed into place once every file verified.
public struct ModelLayout: Sendable {
    public let model: ModelDescriptor
    public let root: URL

    public init(_ model: ModelDescriptor, root: URL) {
        self.model = model
        self.root = root
    }

    public var isFolder: Bool { model.url == nil && model.repository != nil }
    public var directory: URL { root.appendingPathComponent(model.kind.rawValue, isDirectory: true) }
    public var final: URL { directory.appendingPathComponent(model.fileName, isDirectory: isFolder) }
    /// The partial file, or the staging folder of a set.
    public var partial: URL { directory.appendingPathComponent(model.fileName + ".partial", isDirectory: isFolder) }

    /// The top-level entries FluidAudio needs from the repository (bundles and files); empty for single files.
    public var requiredEntries: Set<String> {
        guard isFolder else { return [] }
        switch model.kind {
        case .asr: return ModelNames.ASR.requiredModelsV3(precision: .int8).union([ModelNames.ASR.vocabularyFile])
        case .diarization: return ModelNames.OfflineDiarizer.requiredModels
        case .echoCancel: return [ModelNames.LocalVQE.modelFile(variant: .v13, chunk: .realtime16ms)]
        case .vad: return ModelNames.VAD.requiredModels
        case .llm, .coremlEncoder: return []
        }
    }

    /// Whether the installed copy is complete: the file has its catalog size, or the folder holds every required entry.
    public func isInstalled(fileManager: FileManager = .default) -> Bool {
        if isFolder {
            let entries = requiredEntries
            return !entries.isEmpty && entries.allSatisfy { fileManager.fileExists(atPath: final.appendingPathComponent($0).path) }
        }
        let file = final.resolvingSymlinksInPath()
        guard let size = (try? fileManager.attributesOfItem(atPath: file.path))?[.size] as? Int64 else { return false }
        return model.sha256 == nil || size == model.bytes
    }

    /// Bytes already on disk in the partial file or staging folder.
    public func partialBytes(fileManager: FileManager = .default) -> Int64 {
        isFolder ? ModelLayout.size(of: partial, fileManager: fileManager)
            : ((try? fileManager.attributesOfItem(atPath: partial.path))?[.size] as? Int64 ?? 0)
    }

    static func size(of url: URL, fileManager: FileManager = .default) -> Int64 {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        guard isDirectory.boolValue else { return (try? fileManager.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0 }
        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = fileManager.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        for case let file as URL in walker {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

/// One file to fetch, with the hash that proves it.
public struct RemoteFile: Equatable, Sendable {
    public enum Digest: Equatable, Sendable {
        /// SHA-256 of the content (catalog files and Git LFS objects).
        case sha256(String)
        /// Git blob SHA-1 (`"blob <size>\0" + content`), for the small non-LFS files of a repository.
        case gitBlobSHA1(String)
    }

    public var url: URL
    /// Path under the model's folder ("Encoder.mlmodelc/weights/weight.bin"), or the file name.
    public var path: String
    public var size: Int64
    public var digest: Digest?

    public init(url: URL, path: String, size: Int64, digest: Digest?) {
        self.url = url; self.path = path; self.size = size; self.digest = digest
    }
}

/// Hugging Face URLs, honouring the "mirror" setting (local-models.md §5.2): the mirror replaces the
/// `https://huggingface.co` base for both the file and the API URLs.
enum ModelSource {
    static let huggingFace = "https://huggingface.co"

    static var base: String {
        let mirror = Defaults[.modelMirrorURL].trimmingCharacters(in: .whitespacesAndNewlines)
        return mirror.isEmpty ? huggingFace : (mirror.hasSuffix("/") ? String(mirror.dropLast()) : mirror)
    }

    static func rebased(_ url: URL) -> URL {
        let string = url.absoluteString
        guard base != huggingFace, string.hasPrefix(huggingFace) else { return url }
        return URL(string: base + string.dropFirst(huggingFace.count)) ?? url
    }

    /// The files of a single-file model.
    static func files(of model: ModelDescriptor) -> [RemoteFile] {
        guard let url = model.url else { return [] }
        return [RemoteFile(url: rebased(url), path: model.fileName, size: model.bytes, digest: model.sha256.map(RemoteFile.Digest.sha256))]
    }

    /// Lists a repository at its revision (following the API's `Link` pagination) and keeps the files under the
    /// required entries, each with its size and hash.
    static func files(of layout: ModelLayout, session: URLSession) async throws -> [RemoteFile] {
        guard let repository = layout.model.repository else { return [] }
        let revision = layout.model.revision ?? "main"
        let required = layout.requiredEntries
        var next = URL(string: "\(base)/api/models/\(repository)/tree/\(revision)?recursive=true")
        var files: [RemoteFile] = []
        var pages = 0
        while let url = next, pages < 50 {
            pages += 1
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw ModelError.http(0) }
            guard http.statusCode == 200 else { throw ModelError.http(http.statusCode) }
            guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw ModelError.http(http.statusCode) }
            for item in items where item["type"] as? String == "file" {
                guard let path = item["path"] as? String, let top = path.split(separator: "/").first.map(String.init),
                      required.contains(top) else { continue }
                let lfs = item["lfs"] as? [String: Any]
                let size = (lfs?["size"] as? NSNumber ?? item["size"] as? NSNumber)?.int64Value ?? -1
                let digest: RemoteFile.Digest? = (lfs?["oid"] as? String).map { .sha256($0) }
                    ?? (item["oid"] as? String).map { .gitBlobSHA1($0) }
                let encoded = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
                guard let fileURL = URL(string: "\(base)/\(repository)/resolve/\(revision)/" + encoded.joined(separator: "/")) else { continue }
                files.append(RemoteFile(url: fileURL, path: path, size: size, digest: digest))
            }
            next = nextPage(http)
        }
        let found = Set(files.compactMap { $0.path.split(separator: "/").first.map(String.init) })
        guard found == required else {
            Log.models.error("\(repository, privacy: .public) is missing \(required.subtracting(found).sorted(), privacy: .public)")
            throw ModelError.http(404)
        }
        return files
    }

    /// `Link: <https://…?cursor=…>; rel="next"`.
    static func nextPage(_ response: HTTPURLResponse) -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in link.split(separator: ",") where part.contains("rel=\"next\"") {
            guard let open = part.firstIndex(of: "<"), let close = part.firstIndex(of: ">"), open < close else { continue }
            return URL(string: String(part[part.index(after: open)..<close]))
        }
        return nil
    }
}

/// Streaming SHA-256 or Git blob SHA-1, so a file is hashed while it is written and never read twice.
struct StreamingDigest {
    private var sha256 = SHA256()
    private var sha1 = Insecure.SHA1()
    let kind: RemoteFile.Digest?

    init(_ kind: RemoteFile.Digest?, size: Int64) {
        self.kind = kind
        if case .gitBlobSHA1 = kind { sha1.update(data: Data("blob \(size)\0".utf8)) }
    }

    mutating func update(_ data: Data) {
        switch kind {
        case .sha256: sha256.update(data: data)
        case .gitBlobSHA1: sha1.update(data: data)
        case nil: break
        }
    }

    /// Whether the content matches; true when there is nothing to check against.
    func matches() -> Bool {
        switch kind {
        case .sha256(let expected): sha256.finalize().hex == expected.lowercased()
        case .gitBlobSHA1(let expected): sha1.finalize().hex == expected.lowercased()
        case nil: true
        }
    }

    /// Feeds an existing file (a partial being resumed, or an imported file) through the digest.
    mutating func update(contentsOf url: URL, upTo length: Int64? = nil) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var remaining = length ?? Int64.max
        while remaining > 0 {
            let chunk = try handle.read(upToCount: Int(min(remaining, 8 << 20))) ?? Data()
            if chunk.isEmpty { break }
            update(chunk)
            remaining -= Int64(chunk.count)
        }
    }
}

private extension Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
