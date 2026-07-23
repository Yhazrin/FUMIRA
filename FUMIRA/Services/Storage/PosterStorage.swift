import CoreTransferable
import Foundation
import Photos
import UniformTypeIdentifiers

enum PosterStorageError: LocalizedError, Sendable {
    case emptyImage
    case encodeFailed
    case photoLibraryDenied
    case photoLibraryRestricted
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            "海报还没有准备好，请稍后再试。"
        case .encodeFailed:
            "海报合成失败，请重试。"
        case .photoLibraryDenied:
            "没有相册写入权限。请在设置中允许 FUMIRA 添加照片。"
        case .photoLibraryRestricted:
            "当前设备限制了相册写入，无法保存海报。"
        case .saveFailed(let detail):
            "保存到相册失败：\(detail)"
        }
    }
}

struct PosterSnapshot: Sendable {
    let time: TimePosition
    let title: String
    let yearLabel: String
    /// Composed poster PNG bytes ready for Photos / ShareSheet.
    let imageData: Data
}

protocol PosterStorage: Sendable {
    func save(_ poster: PosterSnapshot) async throws -> URL
}

actor MockPosterStorage: PosterStorage {
    private(set) var savedSnapshots: [PosterSnapshot] = []
    var shouldFail = false

    func save(_ poster: PosterSnapshot) async throws -> URL {
        if shouldFail {
            throw PosterStorageError.saveFailed("mock failure")
        }
        guard !poster.imageData.isEmpty else {
            throw PosterStorageError.emptyImage
        }
        savedSnapshots.append(poster)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fumira-poster-\(UUID().uuidString).png")
        try poster.imageData.write(to: url, options: .atomic)
        return url
    }

    func reset() {
        savedSnapshots = []
        shouldFail = false
    }
}

/// Writes the composed poster PNG into a temp file and into the system photo library.
struct PhotoLibraryPosterStorage: PosterStorage {
    func save(_ poster: PosterSnapshot) async throws -> URL {
        guard !poster.imageData.isEmpty else {
            throw PosterStorageError.emptyImage
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fumira-poster-\(UUID().uuidString).png")
        try poster.imageData.write(to: url, options: .atomic)

        try await Self.ensureAddOnlyAccess()
        try await Self.addPNGFileToPhotoLibrary(url)
        return url
    }

    private static func ensureAddOnlyAccess() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return
        case .notDetermined:
            let next = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            switch next {
            case .authorized, .limited:
                return
            case .denied:
                throw PosterStorageError.photoLibraryDenied
            case .restricted:
                throw PosterStorageError.photoLibraryRestricted
            @unknown default:
                throw PosterStorageError.photoLibraryDenied
            }
        case .denied:
            throw PosterStorageError.photoLibraryDenied
        case .restricted:
            throw PosterStorageError.photoLibraryRestricted
        @unknown default:
            throw PosterStorageError.photoLibraryDenied
        }
    }

    private static func addPNGFileToPhotoLibrary(_ fileURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }) { success, error in
                if success {
                    continuation.resume()
                } else {
                    let detail = error?.localizedDescription ?? "未知错误"
                    continuation.resume(throwing: PosterStorageError.saveFailed(detail))
                }
            }
        }
    }
}

/// Transferable PNG wrapper for `ShareLink` / drag-and-drop.
struct ShareablePosterPNG: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { poster in
            poster.data
        }
    }
}
