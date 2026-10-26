import Foundation

/// The pages of LidAwake Pro. Fixed here, never taken from the settings or the network.
public enum ProOfferLink {
    public static let page = URL(string: "https://erstgebaut.de/lidawake/")!
    public static let germanPage = URL(string: "https://erstgebaut.de/lidawake/de/")!

    /// `language` is the language the app's interface is shown in.
    public static func page(language: String?) -> URL {
        language == "de" ? germanPage : page
    }
}
