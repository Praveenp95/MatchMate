//
//  ImageCache.swift
//  MatchMate
//
//  Created by Praveen P on 09/06/26.
//

import SwiftUI
import Combine

final class ImageCache: @unchecked Sendable {

    static let shared = ImageCache()

    private let memoryCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit     = 100
        cache.totalCostLimit = 50 * 1024 * 1024
        return cache
    }()

    private let diskCacheURL: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Read

    func image(for key: String) -> UIImage? {
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }
        if let image = loadFromDisk(key: key) {
            store(image, inMemory: key)
            return image
        }
        return nil
    }

    // MARK: - Write

    func store(_ image: UIImage, forKey key: String) {
        store(image, inMemory: key)
        saveToDisk(image, key: key)
    }

    // MARK: - Private helpers

    private func store(_ image: UIImage, inMemory key: String) {
        let cost = image.jpegData(compressionQuality: 1)?.count ?? 0
        memoryCache.setObject(image, forKey: key as NSString, cost: cost)
    }

    private func diskURL(for key: String) -> URL {
        let filename = key
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return diskCacheURL.appendingPathComponent(filename)
    }

    private func saveToDisk(_ image: UIImage, key: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: diskURL(for: key), options: .atomic)
    }

    private func loadFromDisk(key: String) -> UIImage? {
        let url = diskURL(for: key)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - ImageLoader

@MainActor
final class ImageLoader: ObservableObject {

    @Published var image: UIImage?
    @Published var isLoading = false

    private let urlString: String
    private var task: Task<Void, Never>?

    init(urlString: String) {
        self.urlString = urlString
        load()
    }

    func load() {
        if let cached = ImageCache.shared.image(for: urlString) {
            image = cached
            return
        }

        guard let url = URL(string: urlString) else { return }
        isLoading = true

        task = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let uiImage = UIImage(data: data) else {
                    isLoading = false
                    return
                }
                ImageCache.shared.store(uiImage, forKey: urlString)
                image     = uiImage
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }

    deinit {
        task?.cancel()
    }
}

// MARK: - CachedAsyncImage SwiftUI view

struct CachedAsyncImage: View {

    @StateObject private var loader: ImageLoader

    init(urlString: String) {
        _loader = StateObject(wrappedValue: ImageLoader(urlString: urlString))
    }

    var body: some View {
        Group {
            if let uiImage = loader.image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if loader.isLoading {
                ZStack {
                    Color.gray.opacity(0.15)
                    ProgressView().tint(.matchTeal)
                }
            } else {
                ZStack {
                    Color.gray.opacity(0.15)
                    Image(systemName: "person.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
    }
}
