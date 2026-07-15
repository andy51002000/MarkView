import Darwin
import Dispatch
import Foundation

final class FileWatcher: @unchecked Sendable {
    private let url: URL
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.markview.file-watcher")
    private var fileSource: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?
    private var snapshot: FileSnapshot?
    private var isStopped = false

    init(
        url: URL,
        debounceInterval: TimeInterval = 0.25,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.url = url.standardizedFileURL
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    func start() {
        queue.sync {
            guard !isStopped else { return }
            snapshot = FileSnapshot(url: url)
            installDirectorySource()
            installFileSource()
        }
    }

    func stop() {
        queue.async { [self] in
            guard !isStopped else { return }
            isStopped = true
            pendingChange?.cancel()
            pendingChange = nil
            fileSource?.cancel()
            fileSource = nil
            directorySource?.cancel()
            directorySource = nil
        }
    }

    private func installFileSource() {
        fileSource?.cancel()
        fileSource = nil

        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        fileSource = source
        source.resume()
    }

    private func installDirectorySource() {
        let directoryURL = url.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleChange()
        }
        source.setCancelHandler {
            close(descriptor)
        }
        directorySource = source
        source.resume()
    }

    private func scheduleChange() {
        guard !isStopped else { return }
        pendingChange?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            let currentSnapshot = FileSnapshot(url: self.url)
            guard currentSnapshot != self.snapshot else { return }
            self.snapshot = currentSnapshot
            self.installFileSource()
            self.onChange()
        }
        pendingChange = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

private struct FileSnapshot: Equatable {
    let device: UInt64
    let inode: UInt64
    let size: UInt64
    let modifiedAt: Date

    init?(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return nil
        }
        self.device = device
        self.inode = inode
        self.size = size
        self.modifiedAt = modifiedAt
    }
}
