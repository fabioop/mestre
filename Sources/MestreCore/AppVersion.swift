import Foundation

/// The version as Settings shows it. Everything below 1.0.0 is the public beta, so the label
/// goes away by itself at 1.0.0. Pre-release and development versions already say what they are.
public enum AppVersion {
    public static func display(_ version: String) -> String {
        let isPlainRelease = !version.contains("-")
        return isPlainRelease && version.hasPrefix("0.") ? "\(version) (beta)" : version
    }
}
