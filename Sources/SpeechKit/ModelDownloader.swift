import Foundation
import SuperFlowCore

/// Fetches one file into its `.partial` with an HTTP `Range` resume, hashing while it writes (local-models.md §5.3).
/// A resumed partial is re-hashed from disk first, so the digest always covers the whole file. Cancelling keeps the
/// partial for the next attempt.
final class FileTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    typealias Progress = @Sendable (_ fileBytes: Int64) -> Void

    private let file: RemoteFile
    private let partial: URL
    private let configuration: URLSessionConfiguration
    private let onProgress: Progress
    private let lock = NSLock()
    private var handle: FileHandle?
    private var digest: StreamingDigest
    private var written: Int64 = 0
    private var offset: Int64 = 0
    private var failure: Error?
    private var continuation: CheckedContinuation<Void, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?

    init(file: RemoteFile, partial: URL, configuration: URLSessionConfiguration, onProgress: @escaping Progress) {
        self.file = file
        self.partial = partial
        self.configuration = configuration
        self.onProgress = onProgress
        digest = StreamingDigest(file.digest, size: file.size)
    }

    /// Downloads (or finishes) the file and verifies it; throws `ModelError` on HTTP errors, a hash mismatch, or a
    /// cancellation, and `URLError` on network failures. The partial is removed only on a hash mismatch.
    func run() async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: partial.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: partial.path) { fm.createFile(atPath: partial.path, contents: nil) }
        offset = (try? fm.attributesOfItem(atPath: partial.path))?[.size] as? Int64 ?? 0
        if file.size > 0, offset > file.size {
            try Data().write(to: partial)
            offset = 0
        }
        if offset > 0 { try digest.update(contentsOf: partial, upTo: offset) }
        written = offset
        onProgress(written)
        if file.size > 0, offset == file.size {
            try verify()
            return
        }
        var request = URLRequest(url: file.url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        if offset > 0 { request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range") }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock {
                    self.continuation = continuation
                    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                    self.session = session
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                    // Cancelled before the task existed: stop it now.
                    if failure != nil { task.cancel() }
                }
            }
        } onCancel: {
            lock.withLock { self.failure = ModelError.cancelled; self.task?.cancel() }
        }
        try verify()
    }

    private func verify() throws {
        if file.size > 0, written != file.size {
            throw URLError(.networkConnectionLost)
        }
        guard digest.matches() else {
            try? FileManager.default.removeItem(at: partial)
            throw ModelError.checksumMismatch
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let disposition: URLSession.ResponseDisposition = lock.withLock {
            do {
                switch status {
                case 206 where offset > 0:
                    handle = try FileHandle(forWritingTo: partial)
                    try handle?.seek(toOffset: UInt64(offset))
                case 200:
                    // The server ignored the range: start over.
                    try Data().write(to: partial)
                    digest = StreamingDigest(file.digest, size: file.size)
                    written = 0
                    handle = try FileHandle(forWritingTo: partial)
                case 416 where offset > 0:
                    // Nothing left to fetch; verification decides whether the partial is whole.
                    return .cancel
                default:
                    failure = ModelError.http(status)
                    return .cancel
                }
                return .allow
            } catch {
                failure = error
                return .cancel
            }
        }
        completionHandler(disposition)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let total: Int64? = lock.withLock {
            guard let handle, failure == nil else { return nil }
            do {
                try handle.write(contentsOf: data)
                digest.update(data)
                written += Int64(data.count)
                return written
            } catch {
                failure = error
                dataTask.cancel()
                return nil
            }
        }
        if let total { onProgress(total) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, result): (CheckedContinuation<Void, Error>?, Error?) = lock.withLock {
            try? handle?.close()
            handle = nil
            let pending = self.continuation
            self.continuation = nil
            let urlError = (error as? URLError).flatMap { $0.code == .cancelled ? nil : $0 }
            return (pending, failure ?? urlError)
        }
        session.finishTasksAndInvalidate()
        if let result { continuation?.resume(throwing: result) } else { continuation?.resume() }
    }
}
