import Foundation

struct ProjectRootResolution: Equatable, Sendable {
    let rootURL: URL
    let marker: String?
    let scannedDirectoryCount: Int
}

enum ProjectRootResolver {
    static let trustedMarkers = [".git", "Package.swift", "README.md"]

    static func resolve(
        documentURL: URL,
        fileManager: FileManager = .default,
        homeURL: URL? = FileManager.default.homeDirectoryForCurrentUser
    ) -> ProjectRootResolution {
        let documentDirectory = canonical(documentURL.deletingLastPathComponent())
        let canonicalHome = homeURL.map(canonical)
        let startsInsideHome = canonicalHome.map {
            contains(documentDirectory, in: $0)
        } ?? false

        var current = documentDirectory
        var scanned = 0

        while true {
            scanned += 1
            if let marker = trustedMarkers.first(where: {
                isTrustedMarker(current.appendingPathComponent($0),
                                name: $0,
                                fileManager: fileManager)
            }) {
                return ProjectRootResolution(
                    rootURL: current,
                    marker: marker,
                    scannedDirectoryCount: scanned
                )
            }

            let parent = canonical(current.deletingLastPathComponent())
            if parent.path == current.path { break }
            if startsInsideHome,
               let canonicalHome,
               !contains(parent, in: canonicalHome) {
                break
            }
            current = parent
        }

        return ProjectRootResolution(
            rootURL: documentDirectory,
            marker: nil,
            scannedDirectoryCount: scanned
        )
    }

    private static func isTrustedMarker(
        _ url: URL,
        name: String,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        return name == ".git" || !isDirectory.boolValue
    }

    static func canonical(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        var existingAncestor = standardized
        var missingSuffix: [String] = []

        while !FileManager.default.fileExists(atPath: existingAncestor.path) {
            let parent = existingAncestor.deletingLastPathComponent()
            guard parent.path != existingAncestor.path else { break }
            missingSuffix.insert(existingAncestor.lastPathComponent, at: 0)
            existingAncestor = parent
        }

        var resolved = existingAncestor.resolvingSymlinksInPath()
        for component in missingSuffix {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }

    static func contains(_ candidate: URL, in root: URL) -> Bool {
        containsCanonical(canonical(candidate), in: canonical(root))
    }

    static func containsCanonical(_ candidate: URL, in root: URL) -> Bool {
        let candidateComponents = candidate.pathComponents
        let rootComponents = root.pathComponents
        guard candidateComponents.count >= rootComponents.count else { return false }
        return Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
