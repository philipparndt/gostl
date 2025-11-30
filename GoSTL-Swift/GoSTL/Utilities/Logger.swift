import Logging
import os.log

enum AppLogger {
    static let main = Logger(label: "com.gostl.app")
    static let rendering = Logger(label: "com.gostl.rendering")
    static let geometry = Logger(label: "com.gostl.geometry")
    static let io = Logger(label: "com.gostl.io")
}
