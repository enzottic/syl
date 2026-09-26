//
//  TagSymbolCatalog.swift
//  FinanceTracker
//
//  The curated SF Symbol list offered when picking a tag icon.
//

import SwiftUI

/// SF Symbols offered in the tag icon picker.
///
/// iOS exposes no API for enumerating SF Symbols, and the full catalog (~6,900 glyphs) would be
/// unusable in a picker anyway, so this is a hand-picked set skewed toward what people actually
/// tag spending with. Entries are validated against the running OS on first access, so a typo or
/// a symbol that predates the deployment target drops out instead of rendering an empty cell.
///
/// Sections mirror `TagEmojiCatalog`, and entries carry keywords for the same reason: a symbol's
/// name often doesn't match how people search for it (`cup.and.saucer.fill` is "coffee").
public enum TagSymbolCatalog {
    public struct Entry: Identifiable, Hashable {
        public let symbol: String
        public let keywords: [String]
        public var id: String { symbol }
    }

    public struct Section: Identifiable {
        public let id: String
        public let title: String
        public let entries: [Entry]
    }

    /// Sections with every unavailable symbol filtered out. Computed once.
    public static let sections: [Section] = rawSections
        .map { Section(id: $0.id, title: $0.title, entries: $0.entries.filter { UIImage(systemName: $0.symbol) != nil }) }
        .filter { !$0.entries.isEmpty }

    /// Sections filtered to entries matching `query`, with empty sections removed. Matches on
    /// keywords, the symbol name, or the section title, so both "coffee" and "cup" find
    /// `cup.and.saucer.fill`. An empty query returns everything.
    public static func sections(matching query: String) -> [Section] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }

        return sections.compactMap { section in
            let matches = section.entries.filter { entry in
                entry.symbol.localizedCaseInsensitiveContains(trimmed)
                    || section.title.localizedCaseInsensitiveContains(trimmed)
                    || entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
            return matches.isEmpty ? nil : Section(id: section.id, title: section.title, entries: matches)
        }
    }

    /// A readable name for VoiceOver, derived from the symbol name: `fork.knife` → "fork knife".
    public static func accessibilityName(for symbol: String) -> String {
        symbol.replacingOccurrences(of: ".", with: " ")
    }

    private static func entry(_ symbol: String, _ keywords: String...) -> Entry {
        Entry(symbol: symbol, keywords: keywords)
    }

    private static let rawSections: [Section] = [
        Section(id: "money", title: "Money", entries: [
            entry("dollarsign.circle.fill", "money", "cash", "dollar"),
            entry("creditcard.fill", "credit", "card", "debit"),
            entry("banknote.fill", "cash", "bill", "money"),
            entry("building.columns.fill", "bank", "savings"),
            entry("chart.line.uptrend.xyaxis", "invest", "stocks", "growth"),
            entry("chart.pie.fill", "chart", "budget", "stats"),
            entry("percent", "interest", "rate", "discount"),
            entry("giftcard.fill", "giftcard", "voucher"),
            entry("wallet.pass.fill", "wallet", "pass"),
            entry("arrow.up.arrow.down", "transfer", "exchange"),
            entry("bitcoinsign.circle.fill", "bitcoin", "crypto"),
            entry("eurosign.circle.fill", "euro"),
            entry("sterlingsign.circle.fill", "pound", "sterling"),
            entry("yensign.circle.fill", "yen"),
        ]),
        Section(id: "food", title: "Food & Drink", entries: [
            entry("fork.knife", "dining", "restaurant", "meal", "food"),
            entry("cup.and.saucer.fill", "coffee", "cafe", "tea", "espresso"),
            entry("mug.fill", "coffee", "tea", "mug"),
            entry("wineglass.fill", "wine", "bar", "drinks", "alcohol"),
            entry("birthday.cake.fill", "cake", "dessert", "birthday"),
            entry("carrot.fill", "vegetables", "produce", "healthy"),
            entry("fish.fill", "seafood", "sushi", "fish"),
            entry("takeoutbag.and.cup.and.straw.fill", "takeout", "fastfood", "delivery"),
            entry("popcorn.fill", "snacks", "movies", "popcorn"),
            entry("waterbottle.fill", "water", "drinks", "bottle"),
            entry("basket.fill", "groceries", "supermarket", "shopping"),
        ]),
        Section(id: "home", title: "Home & Bills", entries: [
            entry("house.fill", "home", "rent", "mortgage"),
            entry("bed.double.fill", "bed", "bedroom", "furniture"),
            entry("sofa.fill", "furniture", "sofa", "livingroom"),
            entry("lightbulb.fill", "electricity", "light", "power"),
            entry("bolt.fill", "power", "electric", "energy"),
            entry("drop.fill", "water", "utilities"),
            entry("flame.fill", "gas", "heating", "heat"),
            entry("wifi", "internet", "broadband", "wifi"),
            entry("phone.fill", "phone", "landline", "call"),
            entry("trash.fill", "trash", "garbage", "waste"),
            entry("wrench.and.screwdriver.fill", "repairs", "tools", "maintenance"),
            entry("hammer.fill", "diy", "renovation", "hammer"),
            entry("paintbrush.fill", "painting", "decorating", "renovation"),
            entry("key.fill", "rent", "keys", "lease"),
            entry("shower.fill", "shower", "bathroom", "plumbing"),
            entry("washer.fill", "laundry", "washing", "appliance"),
            entry("refrigerator.fill", "fridge", "appliance", "kitchen"),
            entry("chair.lounge.fill", "furniture", "chair"),
        ]),
        Section(id: "transport", title: "Transport", entries: [
            entry("car.fill", "car", "driving", "auto"),
            entry("car.2.fill", "carpool", "rideshare", "cars"),
            entry("bus.fill", "bus", "transit", "commute"),
            entry("tram.fill", "tram", "train", "transit"),
            entry("bicycle", "bike", "bicycle", "cycling"),
            entry("scooter", "scooter", "moped"),
            entry("fuelpump.fill", "gas", "fuel", "petrol"),
            entry("parkingsign.circle.fill", "parking"),
            entry("road.lanes", "tolls", "highway", "road"),
            entry("ferry.fill", "ferry", "boat", "transit"),
            entry("figure.walk", "walking", "commute"),
            entry("bolt.car.fill", "ev", "charging", "electric"),
        ]),
        Section(id: "shopping", title: "Shopping", entries: [
            entry("cart.fill", "groceries", "shopping", "supermarket"),
            entry("bag.fill", "shopping", "retail", "purchase"),
            entry("tshirt.fill", "clothes", "clothing", "apparel"),
            entry("shippingbox.fill", "delivery", "package", "online"),
            entry("tag.fill", "sale", "discount", "price"),
            entry("gift.fill", "gift", "present"),
            entry("handbag.fill", "handbag", "purse", "accessories"),
            entry("storefront.fill", "store", "shop", "retail"),
        ]),
        Section(id: "health", title: "Health & Fitness", entries: [
            entry("heart.fill", "health", "wellness", "heart"),
            entry("cross.case.fill", "medical", "firstaid", "doctor"),
            entry("pills.fill", "medicine", "pharmacy", "prescription"),
            entry("stethoscope", "doctor", "checkup", "medical"),
            entry("bandage.fill", "firstaid", "injury", "bandage"),
            entry("figure.run", "running", "exercise", "fitness"),
            entry("dumbbell.fill", "gym", "workout", "fitness"),
            entry("brain.head.profile", "therapy", "mental", "wellness"),
            entry("eye.fill", "optician", "eyecare", "glasses"),
            entry("tooth.fill", "dentist", "dental", "teeth"),
        ]),
        Section(id: "fun", title: "Entertainment", entries: [
            entry("tv.fill", "tv", "streaming", "television"),
            entry("gamecontroller.fill", "games", "gaming", "console"),
            entry("music.note", "music", "song", "spotify"),
            entry("headphones", "headphones", "audio", "podcast"),
            entry("film.fill", "movies", "cinema", "film"),
            entry("ticket.fill", "tickets", "events", "concert"),
            entry("theatermasks.fill", "theater", "show", "play"),
            entry("guitars.fill", "music", "band", "instrument"),
            entry("party.popper.fill", "party", "celebration", "events"),
            entry("sportscourt.fill", "sports", "games"),
            entry("book.fill", "books", "reading"),
        ]),
        Section(id: "work", title: "Work & School", entries: [
            entry("briefcase.fill", "work", "business", "job"),
            entry("laptopcomputer", "laptop", "computer", "software"),
            entry("desktopcomputer", "desktop", "computer", "monitor"),
            entry("printer.fill", "printer", "printing", "office"),
            entry("graduationcap.fill", "school", "education", "tuition"),
            entry("book.closed.fill", "study", "textbook", "course"),
            entry("pencil.and.ruler.fill", "supplies", "stationery", "design"),
            entry("paperclip", "office", "supplies", "documents"),
            entry("envelope.fill", "mail", "postage", "shipping"),
            entry("building.2.fill", "office", "coworking", "building"),
            entry("person.2.fill", "team", "meeting", "clients"),
            entry("calendar", "calendar", "schedule", "planning"),
        ]),
        Section(id: "travel", title: "Travel", entries: [
            entry("airplane", "flight", "plane", "airfare"),
            entry("suitcase.fill", "luggage", "suitcase", "baggage"),
            entry("globe.americas.fill", "world", "international", "globe"),
            entry("map.fill", "map", "trip", "itinerary"),
            entry("beach.umbrella.fill", "beach", "vacation", "holiday"),
            entry("tent.fill", "camping", "tent", "outdoors"),
            entry("mountain.2.fill", "mountains", "hiking", "skiing"),
            entry("binoculars.fill", "sightseeing", "tours"),
            entry("camera.fill", "camera", "photos"),
            entry("sun.max.fill", "summer", "vacation", "sun"),
            entry("snowflake", "winter", "ski", "cold"),
        ]),
        Section(id: "pets", title: "Pets & Family", entries: [
            entry("pawprint.fill", "pets", "animal", "paw"),
            entry("dog.fill", "dog", "puppy", "pet"),
            entry("cat.fill", "cat", "kitten", "pet"),
            entry("bird.fill", "bird", "pet"),
            entry("figure.and.child.holdinghands", "family", "kids", "parenting"),
            entry("stroller.fill", "baby", "childcare", "stroller"),
            entry("teddybear.fill", "toys", "kids", "children"),
        ]),
        Section(id: "tech", title: "Tech & Subscriptions", entries: [
            entry("iphone", "phone", "mobile", "cell"),
            entry("ipad", "tablet", "ipad"),
            entry("applewatch", "watch", "wearable"),
            entry("airpods", "earbuds", "headphones", "audio"),
            entry("externaldrive.fill", "storage", "drive", "backup"),
            entry("icloud.fill", "cloud", "storage", "backup"),
            entry("antenna.radiowaves.left.and.right", "mobile", "data", "service"),
            entry("network", "internet", "network", "hosting"),
            entry("play.rectangle.fill", "streaming", "video", "subscription"),
            entry("newspaper.fill", "news", "subscription", "magazine"),
        ]),
        Section(id: "other", title: "Other", entries: [
            entry("star.fill", "favorite", "important", "star"),
            entry("bookmark.fill", "bookmark", "misc", "tag"),
            entry("flag.fill", "flag", "priority"),
            entry("bell.fill", "reminder", "alert", "notification"),
            entry("lock.fill", "insurance", "secure", "lock"),
            entry("leaf.fill", "eco", "garden", "plants"),
            entry("sparkles", "misc", "other", "sparkle"),
            entry("scissors", "haircut", "grooming", "salon"),
            entry("gearshape.fill", "settings", "general", "admin"),
            entry("questionmark.circle.fill", "unknown", "unsorted", "other"),
            entry("ellipsis.circle.fill", "misc", "other"),
            entry("circle.fill", "dot", "plain", "simple"),
        ]),
    ]
}
