import OSLog

public enum MenuWattDiagnostics {
    public static let app = Logger(subsystem: "MenuWatt", category: "app")
    public static let monitoring = Logger(subsystem: "MenuWatt", category: "monitoring")
    public static let preferences = Logger(subsystem: "MenuWatt", category: "preferences")
}
