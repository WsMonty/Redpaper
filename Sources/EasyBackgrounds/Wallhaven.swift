import Foundation

struct Post {
    let id: String
    let title: String
    let topic: String
    let permalink: String
    let imageURL: URL
    let width: Double
    let height: Double
}

struct RateLimited: LocalizedError {
    var errorDescription: String? { "Wallhaven is limiting requests right now. Try again in a minute." }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Which wallpapers to pick from: the newest, or the most popular of a period.
/// No day or week: per topic, Wallhaven's top lists that short are mostly empty at screen resolution.
enum Sort: String, CaseIterable, Identifiable {
    case new, month, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: "Newest"
        case .month: "Top this month"
        case .year: "Top this year"
        case .all: "Top of all time"
        }
    }
    var query: String {
        switch self {
        case .new: "sorting=date_added"
        case .month: "sorting=toplist&topRange=1M"
        case .year: "sorting=toplist&topRange=1y"
        case .all: "sorting=favorites" // toplist has no "all time" range
        }
    }
}

/// Wallhaven's public API: SFW search needs no key, 45 requests a minute, 24 results a page.
enum Wallhaven {
    static let userAgent = "EasyBackgrounds/1.0 (macOS wallpaper app)"
    static let defaultTopics = ["landscape", "nature", "space"]
    /// The 50 topics with the most SFW wallpapers, measured with the search API (Nov 2026).
    static let popularTopics = [
        "3D", "abstract", "animals", "anime", "architecture", "artwork", "birds", "black background", "building",
        "cars", "city", "city lights", "cityscape", "clouds", "colorful", "computer", "dark", "digital art",
        "fantasy art", "field", "flowers", "forest", "futuristic", "illustration", "lake", "landscape", "macro",
        "minimalism", "mountains", "nature", "night", "ocean", "painting", "photography", "planet", "reflection",
        "road", "science fiction", "sea", "simple background", "sky", "snow", "space", "stars", "sunset", "trees",
        "vehicle", "video games", "water", "winter",
    ]

    /// SFW wallpapers matching `topic`, at least `atleast` pixels, in `sort` order.
    static func fetch(topic: String, sort: Sort, page: Int, atleast: CGSize) async throws -> [Post] {
        // categories=100: "general" only (no anime or people categories); purity=100: SFW only.
        var c = URLComponents(string: "https://wallhaven.cc/api/v1/search?categories=100&purity=100&\(sort.query)")!
        c.queryItems! += [.init(name: "q", value: topic), .init(name: "page", value: String(page))]
        if atleast.width > 0 { c.queryItems!.append(.init(name: "atleast", value: "\(Int(atleast.width))x\(Int(atleast.height))")) }
        var req = URLRequest(url: c.url!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 429 { throw RateLimited() }
        if code >= 500 { throw AppError("Wallhaven is having trouble (\(code)). Easy Backgrounds will try again later.") }
        guard code == 200 else { throw AppError("Wallhaven returned an error (\(code)).") }
        do { return try parse(data, topic: topic) } catch {
            throw AppError("Couldn't read Wallhaven's answer for \"\(topic)\".")
        }
    }

    static func parse(_ data: Data, topic: String) throws -> [Post] {
        struct Response: Decodable {
            struct Item: Decodable {
                let id: String, url: String, path: String, purity: String
                let dimension_x: Double, dimension_y: Double
            }
            let data: [Item]
        }
        return try JSONDecoder().decode(Response.self, from: data).data.compactMap { w in
            guard w.purity == "sfw", let image = URL(string: w.path) else { return nil } // purity=100 already; belt and braces
            return Post(id: w.id, title: "\(topic.capitalized), \(Int(w.dimension_x))×\(Int(w.dimension_y))", topic: topic,
                        permalink: w.url, imageURL: image, width: w.dimension_x, height: w.dimension_y)
        }
    }

    /// 0…1: the worse of shape match and resolution coverage (bigger images count as 1).
    static func fit(imageW w: Double, imageH h: Double, screenW: Double, screenH: Double) -> Double {
        guard w > 0, h > 0, screenW > 0, screenH > 0 else { return 0 }
        let a = w / h, s = screenW / screenH
        return min(min(a, s) / max(a, s), min(1, (w * h) / (screenW * screenH)))
    }

    static func selfTest() {
        precondition(fit(imageW: 3840, imageH: 2160, screenW: 3840, screenH: 2160) == 1)
        precondition(fit(imageW: 7680, imageH: 4320, screenW: 3840, screenH: 2160) == 1)
        precondition(abs(fit(imageW: 1920, imageH: 1080, screenW: 3840, screenH: 2160) - 0.25) < 1e-9)
        precondition(abs(fit(imageW: 2160, imageH: 3840, screenW: 3840, screenH: 2160) - 0.31640625) < 1e-9)
        precondition(fit(imageW: 3840, imageH: 2160, screenW: 3024, screenH: 1964) >= SettingsTab.safeFit) // 16:9 on a MacBook
        precondition(fit(imageW: 6000, imageH: 4000, screenW: 2560, screenH: 1440) >= SettingsTab.safeFit) // 3:2 photo on 16:9
        precondition(fit(imageW: 0, imageH: 0, screenW: 3024, screenH: 1964) == 0)

        let json = #"""
        {"data":[
          {"id":"a1","url":"https://wallhaven.cc/w/a1","path":"https://w.wallhaven.cc/full/a1/wallhaven-a1.jpg",
           "purity":"sfw","dimension_x":3840,"dimension_y":2160,"resolution":"3840x2160"},
          {"id":"b2","url":"https://wallhaven.cc/w/b2","path":"https://w.wallhaven.cc/full/b2/wallhaven-b2.png",
           "purity":"sketchy","dimension_x":2560,"dimension_y":1440}
        ],"meta":{"current_page":1,"last_page":1,"per_page":24,"total":2}}
        """#
        let posts = try! parse(Data(json.utf8), topic: "nature")
        precondition(posts.count == 1 && posts[0].id == "a1" && posts[0].width == 3840)
        precondition(posts[0].imageURL.absoluteString == "https://w.wallhaven.cc/full/a1/wallhaven-a1.jpg")
        precondition(posts[0].title == "Nature, 3840×2160" && posts[0].permalink == "https://wallhaven.cc/w/a1")
    }
}
