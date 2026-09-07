import Foundation
import os

enum Log {
    static let engine = Logger(subsystem: "com.hypertime.app", category: "engine")
    static let panel = Logger(subsystem: "com.hypertime.app", category: "panel")
    static let store = Logger(subsystem: "com.hypertime.app", category: "store")
    static let app = Logger(subsystem: "com.hypertime.app", category: "app")
}
