import Foundation

struct Post {
    let id: String
    let title: String
    let subreddit: String
    let permalink: String
    let imageURL: URL
    let width: Double? // nil: unknown until probed (RSS posts without a size in the title)
    let height: Double?
    let nsfw: Bool
}

struct RateLimited: LocalizedError {
    let reset: Double
    var errorDescription: String? { "Reddit is limiting requests right now. Try again in a few minutes." }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct Unauthorized: LocalizedError {
    var errorDescription: String? { "Reddit rejected the sign-in (401)." }
}

/// Which posts to pick from: the newest, or the most upvoted of a period.
enum Sort: String, CaseIterable, Identifiable {
    case new, day, week, month, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: "Newest"
        case .day: "Top today"
        case .week: "Top this week"
        case .month: "Top this month"
        case .year: "Top this year"
        case .all: "Top of all time"
        }
    }
    var path: String { self == .new ? "new" : "top" }
    var query: String { self == .new ? "" : "t=\(rawValue)&" }
}

enum Reddit {
    static let userAgent = "macos:Redpaper:1.0 (personal wallpaper app)"
    static let presets = ["wallpapers", "wallpaper", "EarthPorn", "WidescreenWallpaper", "SpacePorn"]

    static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_]{2,21}$", options: .regularExpression) != nil
    }

    /// Image posts across `subs` (one combined `r/a+b+c` request), in `sort` order.
    /// Signed in: JSON API. Signed out: the public RSS feed (the public JSON feed is blocked;
    /// RSS allows ~1 request per minute).
    static func fetch(subs: [String], sort: Sort, token: String?) async throws -> [Post] {
        let sub = subs.joined(separator: "+")
        let url = token == nil
            ? "https://www.reddit.com/r/\(sub)/\(sort.path)/.rss?\(sort.query)limit=100"
            : "https://oauth.reddit.com/r/\(sub)/\(sort.path)?\(sort.query)limit=100&raw_json=1"
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let token { req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if code == 401 { throw Unauthorized() }
        if code == 429 { throw RateLimited(reset: Double(http?.value(forHTTPHeaderField: "x-ratelimit-reset") ?? "") ?? 60) }
        if code == 404 { throw AppError("r/\(sub) doesn't exist.") }
        if code == 403 { throw AppError("r/\(sub) is private, banned or blocked (403).") }
        if code >= 500 { throw AppError("Reddit is having trouble (\(code)). Redpaper will try again later.") }
        guard code == 200 else { throw AppError("Reddit returned an error (\(code)).") }
        do { return try token == nil ? parseRSS(data) : parse(data) } catch {
            throw AppError("Couldn't read r/\(sub). Does it exist?")
        }
    }

    static func parseRSS(_ data: Data) throws -> [Post] {
        let atom = AtomParser()
        let parser = XMLParser(data: data)
        parser.delegate = atom
        guard parser.parse() else { throw parser.parserError ?? AppError("Invalid feed.") }
        return atom.entries.compactMap(post)
    }

    private static let linkPattern = try! Regex(#"href="([^"]+)">\[link\]"#)
    private static let sizePattern = try! Regex(#"(\d{3,5})\s*[x×X*]\s*(\d{3,5})"#)

    private static func post(from e: AtomParser.Entry) -> Post? {
        var image: URL?
        if let link = e.content.firstMatch(of: linkPattern)?.output[1].substring, let url = URL(string: String(link)),
           url.host == "i.redd.it", ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
            image = url
        } else if let thumb = URL(string: e.thumbnail), thumb.host == "preview.redd.it" {
            image = URL(string: "https://i.redd.it/" + thumb.lastPathComponent) // galleries: first image, full size
        }
        guard let image else { return nil }
        let size = e.title.firstMatch(of: sizePattern)
        // RSS has no NSFW flag; a title tag is the best signal available.
        return Post(id: e.id.replacingOccurrences(of: "t3_", with: ""), title: e.title, subreddit: e.subreddit,
                    permalink: e.link,
                    imageURL: image,
                    width: size.flatMap { $0.output[1].substring }.flatMap { Double($0) },
                    height: size.flatMap { $0.output[2].substring }.flatMap { Double($0) },
                    nsfw: e.title.localizedCaseInsensitiveContains("nsfw"))
    }

    static func parse(_ data: Data) throws -> [Post] {
        try JSONDecoder().decode(Listing.self, from: data).data.children.compactMap { $0.data.flatMap(post) }
    }

    private static func post(from p: RawPost) -> Post? {
        let link = "https://www.reddit.com" + p.permalink
        if let src = p.preview?.images.first?.source, let url = URL(string: p.url),
           ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()) {
            return Post(id: p.id, title: p.title, subreddit: p.subreddit, permalink: link, imageURL: url,
                        width: src.width, height: src.height, nsfw: p.over_18)
        }
        // Gallery: use its first image.
        if let mediaID = p.gallery_data?.items.first?.media_id, let media = p.media_metadata?[mediaID],
           let w = media.s?.x, let h = media.s?.y, let ext = media.m?.split(separator: "/").last,
           let url = URL(string: "https://i.redd.it/\(mediaID).\(ext)") {
            return Post(id: p.id, title: p.title, subreddit: p.subreddit, permalink: link, imageURL: url, width: w, height: h, nsfw: p.over_18)
        }
        return nil
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
        {"data":{"children":[
          {"data":{"id":"a","title":"T","subreddit":"x","permalink":"/r/x/a/","url":"https://i.redd.it/a.jpg","over_18":false,
                   "preview":{"images":[{"source":{"width":3840,"height":2160}}]}}},
          {"data":{"id":"b","title":"G","subreddit":"x","permalink":"/r/x/b/","url":"https://www.reddit.com/gallery/b","over_18":true,
                   "gallery_data":{"items":[{"media_id":"m1"}]},"media_metadata":{"m1":{"m":"image/png","s":{"x":2560,"y":1440}}}}},
          {"data":{"id":"c","title":"Self post","permalink":"/r/x/c/","url":"https://www.reddit.com/r/x/c/","over_18":false}},
          {"data":{"broken":true}}
        ]}}
        """#
        let posts = try! parse(Data(json.utf8))
        precondition(posts.count == 2)
        precondition(posts[0].imageURL.absoluteString == "https://i.redd.it/a.jpg" && posts[0].width == 3840)
        precondition(posts[1].imageURL.absoluteString == "https://i.redd.it/m1.png" && posts[1].nsfw)

        let rss = #"""
        <?xml version="1.0" encoding="UTF-8"?><feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
        <title>newest submissions : x</title><link rel="self" href="https://www.reddit.com/r/x/new/.rss"/>
        <entry><content type="html">&lt;span&gt;&lt;a href=&quot;https://i.redd.it/abc.png&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt;</content><id>t3_1</id><category term="x" label="r/x"/>
          <media:thumbnail url="https://preview.redd.it/abc.png?width=640&amp;s=x" /><link href="https://www.reddit.com/r/x/comments/1/a/" /><title>Dolomites [5120 x 2880]</title></entry>
        <entry><content type="html">&lt;a href=&quot;https://www.reddit.com/gallery/2&quot;&gt;[link]&lt;/a&gt;</content><id>t3_2</id>
          <media:thumbnail url="https://preview.redd.it/gal1.jpg?width=140" /><link href="https://www.reddit.com/r/x/comments/2/b/" /><title>Gallery [NSFW] 6144×3456</title></entry>
        <entry><content type="html">&lt;a href=&quot;https://www.deviantart.com/x&quot;&gt;[link]&lt;/a&gt;</content><id>t3_3</id>
          <media:thumbnail url="https://b.thumbs.redditmedia.com/x.jpg" /><link href="https://www.reddit.com/r/x/comments/3/c/" /><title>Art</title></entry>
        <entry><content type="html">&lt;a href=&quot;https://i.redd.it/nosize.jpeg&quot;&gt;[link]&lt;/a&gt;</content><id>t3_4</id>
          <link href="https://www.reddit.com/r/x/comments/4/d/" /><title>No size here</title></entry>
        </feed>
        """#
        let feed = try! parseRSS(Data(rss.utf8))
        precondition(feed.map(\.id) == ["1", "2", "4"])
        precondition(feed[0].imageURL.absoluteString == "https://i.redd.it/abc.png" && feed[0].width == 5120 && feed[0].height == 2880)
        precondition(feed[0].permalink == "https://www.reddit.com/r/x/comments/1/a/" && !feed[0].nsfw && feed[0].subreddit == "x")
        precondition(feed[1].imageURL.absoluteString == "https://i.redd.it/gal1.jpg" && feed[1].width == 6144 && feed[1].nsfw)
        precondition(feed[2].width == nil)
    }
}

private final class AtomParser: NSObject, XMLParserDelegate {
    struct Entry { var id = "", title = "", subreddit = "", link = "", content = "", thumbnail = "" }
    private(set) var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "entry": current = Entry()
        case "link": if let href = attributes["href"] { current?.link = href }
        case "media:thumbnail": current?.thumbnail = attributes["url"] ?? ""
        case "category": current?.subreddit = attributes["term"] ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch name {
        case "entry": if let current { entries.append(current) }; current = nil
        case "id": current?.id = text
        case "title": current?.title = text
        case "content": current?.content = text
        default: break
        }
    }
}

private struct Listing: Decodable {
    struct Child: Decodable {
        enum K: CodingKey { case data }
        let data: RawPost?
        // One odd post shouldn't fail the whole listing.
        init(from decoder: Decoder) throws {
            data = try? decoder.container(keyedBy: K.self).decode(RawPost.self, forKey: .data)
        }
    }
    struct Inner: Decodable { let children: [Child] }
    let data: Inner
}

private struct RawPost: Decodable {
    struct Source: Decodable { let width: Double; let height: Double }
    struct Image: Decodable { let source: Source }
    struct Preview: Decodable { let images: [Image] }
    struct Gallery: Decodable { struct Item: Decodable { let media_id: String }; let items: [Item] }
    struct Media: Decodable { struct Size: Decodable { let x: Double?; let y: Double? }; let m: String?; let s: Size? }

    let id: String
    let title: String
    let subreddit: String
    let permalink: String
    let url: String
    let over_18: Bool
    let preview: Preview?
    let gallery_data: Gallery?
    let media_metadata: [String: Media]?
}
