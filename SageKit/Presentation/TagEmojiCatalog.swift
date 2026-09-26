//
//  TagEmojiCatalog.swift
//  FinanceTracker
//
//  The curated emoji list offered when picking a tag mark.
//

import SwiftUI

/// Emoji offered in the tag picker, in the same sections as `TagSymbolCatalog` so switching
/// between the Icon and Emoji tabs lands the user in the same conceptual place.
///
/// Emoji carry no searchable names the way SF Symbols do (`fork.knife` reads as "fork knife"),
/// so each entry ships its own keywords. The list is deliberately curated rather than exhaustive
/// — the system emoji keyboard remains available in the picker for anything not covered here.
public enum TagEmojiCatalog {
    public struct Entry: Identifiable, Hashable {
        public let emoji: String
        public let keywords: [String]
        public var id: String { emoji }
    }

    public struct Section: Identifiable {
        public let id: String
        public let title: String
        public let entries: [Entry]
    }

    /// Sections with duplicates removed, keeping each emoji's first appearance so a single tap
    /// can never highlight two cells at once.
    public static let sections: [Section] = {
        var seen: Set<String> = []
        return rawSections.compactMap { section in
            let entries = section.entries.filter { seen.insert($0.emoji).inserted }
            return entries.isEmpty ? nil : Section(id: section.id, title: section.title, entries: entries)
        }
    }()

    /// Sections filtered to entries matching `query`, with empty sections removed. Matches on
    /// keywords, the section title, or the emoji itself so a pasted emoji finds its own cell.
    /// An empty query returns everything.
    public static func sections(matching query: String) -> [Section] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }

        return sections.compactMap { section in
            let matches = section.entries.filter { entry in
                entry.emoji == trimmed
                    || section.title.localizedCaseInsensitiveContains(trimmed)
                    || entry.keywords.contains { $0.localizedCaseInsensitiveContains(trimmed) }
            }
            return matches.isEmpty ? nil : Section(id: section.id, title: section.title, entries: matches)
        }
    }

    private static func entry(_ emoji: String, _ keywords: String...) -> Entry {
        Entry(emoji: emoji, keywords: keywords)
    }

    private static let rawSections: [Section] = [
        Section(id: "money", title: "Money", entries: [
            entry("💰", "money", "bag", "cash"), entry("💵", "dollar", "cash", "bill"),
            entry("💳", "credit", "card", "debit"), entry("🏦", "bank", "savings"),
            entry("📈", "invest", "stocks", "growth"), entry("📊", "chart", "stats", "budget"),
            entry("🪙", "coin", "change"), entry("💸", "spending", "expense", "outgoing"),
            entry("🧾", "receipt", "invoice", "bill"), entry("💎", "gem", "luxury", "valuable"),
            entry("🏧", "atm", "withdrawal", "cash"), entry("💶", "euro"),
            entry("💷", "pound", "sterling"), entry("💴", "yen"),
        ]),
        Section(id: "food", title: "Food & Drink", entries: [
            entry("🍽️", "dining", "restaurant", "meal"), entry("☕", "coffee", "cafe", "espresso"),
            entry("🍵", "tea", "matcha"), entry("🍺", "beer", "pub", "drinks"),
            entry("🍷", "wine", "bar", "drinks"), entry("🍔", "burger", "fastfood"),
            entry("🍕", "pizza", "takeout"), entry("🌮", "taco", "mexican"),
            entry("🍣", "sushi", "japanese"), entry("🥗", "salad", "healthy", "groceries"),
            entry("🥐", "bakery", "pastry", "croissant"), entry("🍰", "cake", "dessert", "sweets"),
            entry("🍦", "icecream", "dessert"), entry("🥤", "soda", "drink", "softdrink"),
            entry("🧃", "juice", "drink"), entry("🍎", "fruit", "apple", "produce"),
            entry("🍜", "noodles", "ramen", "soup"), entry("🛒", "groceries", "supermarket", "cart"),
        ]),
        Section(id: "home", title: "Home & Bills", entries: [
            entry("🏠", "home", "house", "rent"), entry("🛋️", "furniture", "sofa", "livingroom"),
            entry("🛏️", "bed", "bedroom", "mattress"), entry("💡", "electricity", "light", "power"),
            entry("⚡", "power", "electric", "energy"), entry("💧", "water", "utilities"),
            entry("🔥", "gas", "heating", "heat"), entry("📶", "internet", "wifi", "broadband"),
            entry("🗑️", "trash", "garbage", "waste"), entry("🧰", "repairs", "tools", "maintenance"),
            entry("🔨", "hammer", "diy", "renovation"), entry("🧹", "cleaning", "housekeeping"),
            entry("🧺", "laundry", "washing"), entry("🔑", "rent", "keys", "mortgage"),
            entry("🚿", "shower", "bathroom", "plumbing"), entry("🪴", "plants", "decor"),
        ]),
        Section(id: "transport", title: "Transport", entries: [
            entry("🚗", "car", "driving", "auto"), entry("🚌", "bus", "transit"),
            entry("🚆", "train", "rail", "commute"), entry("🚇", "subway", "metro", "underground"),
            entry("🚲", "bike", "bicycle", "cycling"), entry("🛵", "scooter", "moped"),
            entry("⛽", "gas", "fuel", "petrol"), entry("🅿️", "parking"),
            entry("🚕", "taxi", "cab", "rideshare"), entry("🚦", "traffic", "tolls"),
            entry("🔧", "maintenance", "servicing", "mechanic"), entry("🛞", "tires", "wheel"),
        ]),
        Section(id: "shopping", title: "Shopping", entries: [
            entry("🛍️", "shopping", "retail", "bags"), entry("👕", "clothes", "clothing", "shirt"),
            entry("👟", "shoes", "sneakers", "footwear"), entry("👗", "dress", "clothing"),
            entry("📦", "package", "delivery", "online"), entry("🏷️", "sale", "tag", "discount"),
            entry("🎁", "gift", "present"), entry("💄", "makeup", "cosmetics", "beauty"),
            entry("👜", "handbag", "purse", "accessories"), entry("🕶️", "sunglasses", "accessories"),
            entry("💍", "jewelry", "ring"), entry("🪑", "furniture", "chair"),
        ]),
        Section(id: "health", title: "Health & Fitness", entries: [
            entry("❤️", "health", "heart", "wellness"), entry("💊", "medicine", "pills", "pharmacy"),
            entry("🏥", "hospital", "medical", "clinic"), entry("🩺", "doctor", "checkup", "medical"),
            entry("🦷", "dentist", "teeth", "dental"), entry("👓", "glasses", "optician", "eyecare"),
            entry("🏋️", "gym", "workout", "fitness"), entry("🏃", "running", "exercise"),
            entry("🧘", "yoga", "meditation", "wellness"), entry("🩹", "bandage", "firstaid"),
            entry("💉", "vaccine", "shot", "injection"), entry("🧴", "skincare", "lotion"),
        ]),
        Section(id: "fun", title: "Entertainment", entries: [
            entry("🍿", "movies", "cinema", "popcorn"), entry("🎬", "film", "movie", "streaming"),
            entry("🎮", "games", "gaming", "console"), entry("🎵", "music", "song"),
            entry("🎧", "headphones", "audio", "podcast"), entry("🎤", "concert", "karaoke", "singing"),
            entry("🎫", "tickets", "events"), entry("🎭", "theater", "show", "play"),
            entry("🎸", "guitar", "band", "instrument"), entry("⚽", "soccer", "football", "sports"),
            entry("🏀", "basketball", "sports"), entry("📚", "books", "reading"),
            entry("🎨", "art", "hobby", "painting"), entry("🎳", "bowling", "activities"),
        ]),
        Section(id: "work", title: "Work & School", entries: [
            entry("💼", "work", "business", "job"), entry("💻", "laptop", "computer", "software"),
            entry("🖥️", "desktop", "monitor", "computer"), entry("🖨️", "printer", "printing"),
            entry("🎓", "school", "education", "tuition"), entry("📖", "study", "textbook", "course"),
            entry("✏️", "pencil", "supplies", "stationery"), entry("📎", "office", "supplies"),
            entry("✉️", "mail", "postage", "shipping"), entry("🏢", "office", "building", "coworking"),
            entry("👥", "team", "meeting", "clients"), entry("📅", "calendar", "schedule", "planning"),
        ]),
        Section(id: "travel", title: "Travel", entries: [
            entry("✈️", "flight", "plane", "airfare"), entry("🏨", "hotel", "accommodation", "stay"),
            entry("🗺️", "map", "trip", "itinerary"), entry("🏖️", "beach", "vacation", "holiday"),
            entry("⛺", "camping", "tent", "outdoors"), entry("🏔️", "mountains", "hiking", "skiing"),
            entry("🧳", "luggage", "suitcase", "baggage"), entry("📷", "camera", "photos"),
            entry("🌍", "world", "globe", "international"), entry("🚢", "cruise", "ship", "ferry"),
            entry("🎡", "attractions", "sightseeing"), entry("🛂", "passport", "visa", "customs"),
        ]),
        Section(id: "pets", title: "Pets & Family", entries: [
            entry("🐾", "pets", "paw", "animal"), entry("🐶", "dog", "puppy"),
            entry("🐱", "cat", "kitten"), entry("🐦", "bird"),
            entry("🐟", "fish", "aquarium"), entry("👶", "baby", "infant"),
            entry("🍼", "baby", "formula", "bottle"), entry("🧸", "toys", "kids", "teddy"),
            entry("👨‍👩‍👧", "family", "household"), entry("🚼", "childcare", "daycare", "nursery"),
            entry("🦴", "petfood", "bone", "treats"), entry("🐕‍🦺", "vet", "petcare"),
        ]),
        Section(id: "tech", title: "Tech & Subscriptions", entries: [
            entry("📱", "phone", "mobile", "cell"), entry("⌚", "watch", "wearable"),
            entry("📺", "tv", "streaming", "television"), entry("☁️", "cloud", "storage", "backup"),
            entry("🔌", "charger", "cable", "accessories"), entry("🖱️", "mouse", "peripheral"),
            entry("⌨️", "keyboard", "peripheral"), entry("📡", "satellite", "cable", "service"),
            entry("🎙️", "podcast", "microphone", "recording"), entry("🕹️", "gaming", "subscription", "arcade"),
            entry("💾", "storage", "data", "hosting"), entry("🔋", "battery", "power"),
        ]),
        Section(id: "other", title: "Other", entries: [
            entry("⭐", "star", "favorite", "important"), entry("🔖", "bookmark", "tag", "misc"),
            entry("🚩", "flag", "priority"), entry("🔔", "reminder", "alert", "notification"),
            entry("🔒", "secure", "lock", "insurance"), entry("🌱", "garden", "plant", "eco"),
            entry("✨", "misc", "sparkle", "other"), entry("✂️", "scissors", "haircut", "grooming"),
            entry("⚙️", "settings", "general", "admin"), entry("❓", "unknown", "unsorted", "other"),
            entry("🎯", "goal", "target", "savings"), entry("🤝", "donation", "charity", "giving"),
        ]),
    ]
}
