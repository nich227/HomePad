import CoreImage
import Foundation
import HomePadUICore
import ImageIO
import Observation
import Photos
import UIKit
import Vision

public struct FacePhoto: Identifiable, Sendable {
    public let id: String
    public let image: UIImage

    public init(id: String, image: UIImage) {
        self.id = id
        self.image = image
    }
}

/// Photos the household chose for the Photos face and the photo widget, kept as files in the
/// app's own storage, plus an optional shared album read from the photo library.
@MainActor
@Observable
public final class FacePhotoLibrary {
    public private(set) var picked: [FacePhoto] = []
    public private(set) var album: [FacePhoto] = []
    /// False after the person declined photo library access for the shared album.
    public private(set) var albumAccessGranted = true
    /// The subject of each photo cut out from its background, keyed by photo id.
    public private(set) var subjects: [String: UIImage] = [:]

    public static let limit = 40
    private nonisolated static let maximumPixelSize = 2048

    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private var loadedAlbumName: String?
    @ObservationIgnored private var subjectsInFlight: Set<String> = []

    /// A nil directory keeps photos in memory only, for previews.
    public init(directory: URL?, picked: [FacePhoto] = []) {
        self.directory = directory
        self.picked = picked
        loadFromDisk()
    }

    public func photos(for source: PhotosSource) -> [FacePhoto] {
        switch source {
        case .picked: picked
        case .sharedAlbum: album.isEmpty ? picked : album
        }
    }

    /// Adds image data from the photo picker. Returns false when the data is not an image or
    /// the library is full.
    @discardableResult
    public func add(imageData: Data) async -> Bool {
        guard picked.count < Self.limit else { return false }
        let maximum = Self.maximumPixelSize
        guard let image = await Task.detached(operation: { Self.downsampled(imageData, maximumPixelSize: maximum) }).value else { return false }
        let id = UUID().uuidString
        if let directory, let jpeg = image.jpegData(compressionQuality: 0.85) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? jpeg.write(to: directory.appendingPathComponent("\(id).jpg"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        picked.append(FacePhoto(id: id, image: image))
        return true
    }

    public func remove(id: String) {
        picked.removeAll { $0.id == id }
        subjects[id] = nil
        if let directory {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).jpg"))
        }
    }

    /// Loads up to `limit` photos from a shared album. An empty name means the first shared album.
    public func loadSharedAlbum(named name: String) async {
        guard loadedAlbumName != name else { return }
        guard UsageDescriptions.has("NSPhotoLibraryUsageDescription") else {
            albumAccessGranted = false
            return
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            albumAccessGranted = false
            return
        }
        albumAccessGranted = true
        loadedAlbumName = name
        let images = await Self.sharedAlbumImages(named: name, limit: 24)
        album = images.enumerated().map { FacePhoto(id: "album-\($0.offset)", image: $0.element) }
    }

    /// Finds the subject of a photo so the Photos face can draw the time behind it. The result
    /// arrives later through `subjects`.
    public func prepareSubject(for photo: FacePhoto) {
        guard subjects[photo.id] == nil, !subjectsInFlight.contains(photo.id) else { return }
        subjectsInFlight.insert(photo.id)
        let image = photo.image
        let id = photo.id
        Task { [weak self] in
            let subject = await Self.liftSubject(from: image)
            self?.subjectsInFlight.remove(id)
            if let subject {
                self?.subjects[id] = subject
            }
        }
    }

    private func loadFromDisk() {
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        let stored = files
            .filter { $0.pathExtension == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(Self.limit)
            .compactMap { url -> FacePhoto? in
                guard let image = UIImage(contentsOfFile: url.path) else { return nil }
                return FacePhoto(id: url.deletingPathExtension().lastPathComponent, image: image)
            }
        picked += stored
    }

    private nonisolated static func downsampled(_ data: Data, maximumPixelSize: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private nonisolated static func liftSubject(from image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let handler = ImageRequestHandler(cgImage)
        guard let observation = try? await handler.perform(GenerateForegroundInstanceMaskRequest()),
              !observation.allInstances.isEmpty,
              let buffer = try? observation.generateMaskedImage(for: observation.allInstances, imageFrom: handler) else { return nil }
        let masked = CIImage(cvPixelBuffer: buffer)
        guard let output = CIContext().createCGImage(masked, from: masked.extent) else { return nil }
        return UIImage(cgImage: output)
    }

    private nonisolated static func sharedAlbumImages(named name: String, limit: Int) async -> [UIImage] {
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumCloudShared, options: nil)
        var match: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if name.isEmpty || collection.localizedTitle?.localizedCaseInsensitiveCompare(name) == .orderedSame {
                match = collection
                stop.pointee = true
            }
        }
        guard let match else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(in: match, options: options)
        var identifiers: [String] = []
        assets.enumerateObjects { asset, _, _ in identifiers.append(asset.localIdentifier) }
        var images: [UIImage] = []
        for identifier in identifiers {
            if let image = await requestImage(localIdentifier: identifier) {
                images.append(image)
            }
        }
        return images
    }

    private nonisolated static func requestImage(localIdentifier: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        // High quality delivery calls the handler exactly once, which a continuation requires.
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.resizeMode = .exact
        let size = CGSize(width: maximumPixelSize, height: maximumPixelSize)
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
