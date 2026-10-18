import Foundation
import Network
import SuperFlowCore

/// What the automatic queue needs to know about the Mac right now (`AutoDownloadPolicy`).
public struct DownloadConditions: Equatable, Sendable {
    /// A satisfied path that is neither expensive (hotspot) nor constrained (Low Data Mode).
    public var networkUsable: Bool
    public var lowPowerMode: Bool
    /// Free space on the models volume ("important usage" capacity, which counts purgeable space).
    public var freeBytes: Int64

    public init(networkUsable: Bool, lowPowerMode: Bool, freeBytes: Int64) {
        self.networkUsable = networkUsable; self.lowPowerMode = lowPowerMode; self.freeBytes = freeBytes
    }
}

/// The source of `DownloadConditions`; the self-test substitutes its own.
@MainActor
public protocol DownloadEnvironment: AnyObject {
    var conditions: DownloadConditions { get }
    /// Called on the main actor when the network path or the power state changes.
    var onChange: (() -> Void)? { get set }
}

/// The rules of `AutoDownloadPolicy` as one decision: why the automatic queue must wait, or nil to proceed.
public enum AutoDownloadGate {
    public static func blocker(enabled: Bool, busy: Bool, conditions: DownloadConditions, diskRetryAfter: TimeInterval,
                               now: Date) -> AutoDownloadStatus? {
        guard enabled else { return .disabled }
        if !conditions.networkUsable { return .waitingForNetwork }
        if AutoDownloadPolicy.pausesInLowPowerMode, conditions.lowPowerMode { return .waitingForPower }
        if conditions.freeBytes < AutoDownloadPolicy.minimumFreeDisk || now.timeIntervalSince1970 < diskRetryAfter {
            return .waitingForDisk(freeBytes: conditions.freeBytes)
        }
        if AutoDownloadPolicy.yieldsWhileBusy, busy { return .waitingWhileBusy }
        return nil
    }
}

/// The real Mac: `NWPathMonitor` for the network, the Low Power Mode notification, and the models volume's capacity.
@MainActor
final class SystemDownloadEnvironment: DownloadEnvironment {
    var onChange: (() -> Void)?
    private let monitor = NWPathMonitor()
    private var path: NWPath?
    private var powerObserver: NSObjectProtocol?
    private let volume: () -> URL

    init(volume: @escaping () -> URL) {
        self.volume = volume
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self else { return }
                let changed = self.path.map { Self.usable($0) != Self.usable(path) } ?? true
                self.path = path
                if changed { self.onChange?() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.udsy.superflow.models.network"))
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onChange?() }
        }
    }

    var conditions: DownloadConditions {
        let free = (try? volume().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return DownloadConditions(networkUsable: path.map(Self.usable) ?? false,
                                  lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled, freeBytes: free)
    }

    private static func usable(_ path: NWPath) -> Bool {
        path.status == .satisfied
            && (AutoDownloadPolicy.allowsExpensiveNetwork || !path.isExpensive)
            && (AutoDownloadPolicy.allowsConstrainedNetwork || !path.isConstrained)
    }
}
