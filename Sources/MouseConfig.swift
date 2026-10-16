import Foundation

enum SideButtonMode: String, Codable {
    case navigation = "navigation"
    case tabs = "tabs"
    case segments = "segments"
    case disabled = "disabled"
}

struct MouseConfig: Codable {
    var sideButtonMode: SideButtonMode = .tabs
    var doubleClickSegments: Bool = true
    var smoothScroll: Bool = true
    var invertScroll: Bool = false
    var scrollMultiplier: Double = 1.0
    var cursorMultiplier: Double = 1.0

    enum CodingKeys: String, CodingKey {
        case sideButtonMode
        case doubleClickSegments
        case smoothScroll
        case invertScroll
        case scrollMultiplier
        case cursorMultiplier
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sideButtonMode = try container.decodeIfPresent(SideButtonMode.self, forKey: .sideButtonMode) ?? .tabs
        self.doubleClickSegments = try container.decodeIfPresent(Bool.self, forKey: .doubleClickSegments) ?? true
        self.smoothScroll = try container.decodeIfPresent(Bool.self, forKey: .smoothScroll) ?? true
        self.invertScroll = try container.decodeIfPresent(Bool.self, forKey: .invertScroll) ?? false
        self.scrollMultiplier = try container.decodeIfPresent(Double.self, forKey: .scrollMultiplier) ?? 1.0
        self.cursorMultiplier = try container.decodeIfPresent(Double.self, forKey: .cursorMultiplier) ?? 1.0
    }

    static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/hyperx")
    }

    static var configFile: URL {
        return configDirectory.appendingPathComponent("config.json")
    }

    static func load() -> MouseConfig {
        let file = configFile
        guard let data = try? Data(contentsOf: file),
              let config = try? JSONDecoder().decode(MouseConfig.self, from: data) else {
            let def = MouseConfig()
            def.save()
            return def
        }
        return config
    }

    func save() {
        let dir = MouseConfig.configDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(self) {
            try? data.write(to: MouseConfig.configFile)
        }
    }
}
