import Foundation
import SwiftUI

struct SpreadsheetConfig: Identifiable, Codable, Hashable {
    var id = UUID()
    var alias: String
    var url: String
    var sheetID: String
    var selectedTab: String
    var description: String

    enum CodingKeys: String, CodingKey {
        case id, alias, url, sheetID, selectedTab, description
    }
}

class SpreadsheetConfigManager: ObservableObject {
    static let shared = SpreadsheetConfigManager()

    @Published var configs: [SpreadsheetConfig] = []

    private let key = "SavedSpreadsheetConfigs"

    private init() {
        loadConfigs()
    }

    func loadConfigs() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SpreadsheetConfig].self, from: data) {
            self.configs = decoded
        }
    }

    func saveConfigs() {
        if let encoded = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }

    func addConfig(_ config: SpreadsheetConfig) {
        configs.append(config)
        saveConfigs()
        syncToPython()
    }

    func removeConfig(at offsets: IndexSet) {
        configs.remove(atOffsets: offsets)
        saveConfigs()
        syncToPython()
    }

    func removeConfig(_ config: SpreadsheetConfig) {
        configs.removeAll { $0.id == config.id }
        saveConfigs()
        syncToPython()
    }

    func syncToPython() {
        SocketClient.shared.sendSpreadsheetConfigs(configs)
    }
}
