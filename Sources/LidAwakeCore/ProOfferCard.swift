import Foundation

/// The LidAwake Pro card above the settings.
public enum ProOfferCard: Equatable {
    case plain
    case discount(UpdateOffer)

    /// `offer` is what `UpdateChecker.offer` gives, so it is nil when the check is off.
    public static func card(isShown: Bool, offer: UpdateOffer?) -> ProOfferCard? {
        guard isShown else { return nil }
        return offer.map(ProOfferCard.discount) ?? .plain
    }
}

/// Prices and the last day of an offer, written the way the interface language writes them.
public enum OfferFormat {
    /// `language` is the language the app's interface is shown in.
    public static func price(_ amount: Decimal, language: String?) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale(language)
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount) EUR"
    }

    public static func day(_ date: Date, language: String?, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(language)
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: date)
    }

    private static func locale(_ language: String?) -> Locale {
        Locale(identifier: language ?? "en")
    }
}
