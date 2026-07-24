import Foundation

enum ChineseInputSchemeID: String, CaseIterable {
    case cangjie = "cangjie"
    case stroke = "stroke"
    case bopomofo = "bopomofo"
    case jyutping = "jyutping"
    case dayi = "dayi"
}

struct ChineseInputSchemeDescriptor: Equatable, Identifiable {
    let id: ChineseInputSchemeID
    let titleZH: String
    let titleEN: String
    let shortTitleZH: String
    let shortTitleEN: String
    let systemImage: String
}

enum ChineseInputSchemeRegistry {
    static let defaultsKey = "kb.inputScheme"
    static let defaultScheme: ChineseInputSchemeID = .cangjie

    private static let builtIn: [ChineseInputSchemeDescriptor] = [
        .init(
            id: .cangjie,
            titleZH: "繁體倉頡 / 速成",
            titleEN: "Cangjie / Quick",
            shortTitleZH: "倉頡 / 速成",
            shortTitleEN: "Cangjie / Quick",
            systemImage: "keyboard"
        ),
        .init(
            id: .stroke,
            titleZH: "繁體筆劃",
            titleEN: "Traditional Stroke",
            shortTitleZH: "筆劃",
            shortTitleEN: "Stroke",
            systemImage: "scribble.variable"
        ),
        .init(
            id: .bopomofo,
            titleZH: "繁體注音",
            titleEN: "Traditional Bopomofo",
            shortTitleZH: "注音",
            shortTitleEN: "Bopomofo",
            systemImage: "character.book.closed"
        ),
        .init(
            id: .jyutping,
            titleZH: "廣東話拼音",
            titleEN: "Cantonese Jyutping",
            shortTitleZH: "廣拼",
            shortTitleEN: "Jyutping",
            systemImage: "character.cursor.ibeam"
        )
    ]

    private static let dayi = ChineseInputSchemeDescriptor(
        id: .dayi,
        titleZH: "繁體大易",
        titleEN: "Traditional Dayi",
        shortTitleZH: "大易",
        shortTitleEN: "Dayi",
        systemImage: "square.grid.3x3"
    )

    /// Proprietary input schemes are exposed only when their licensed resource
    /// passes the bundled metadata/schema check.
    static var available: [ChineseInputSchemeDescriptor] {
        // Keep the licensed resource private until Dayi has its own key layout,
        // decoder and commit path. A valid database alone must not expose a
        // selectable input method that would otherwise fall through to Cangjie.
        #if DEBUG
        // Developer-installed test builds keep Bopomofo available for QA.
        return builtIn
        #else
        // Hide Bopomofo from Archive/App Store builds until its data licensing
        // has been confirmed. `normalized` safely falls back persisted installs
        // that previously selected it to the default Cangjie/Quick scheme.
        return builtIn.filter { $0.id != .bopomofo }
        #endif
    }

    static func normalized(_ raw: String?) -> ChineseInputSchemeID {
        guard let raw else { return defaultScheme }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let scheme = ChineseInputSchemeID(rawValue: value),
              available.contains(where: { $0.id == scheme }) else {
            return defaultScheme
        }
        return scheme
    }

    static func descriptor(for scheme: ChineseInputSchemeID) -> ChineseInputSchemeDescriptor {
        available.first(where: { $0.id == scheme }) ?? available[0]
    }

    static func next(after current: ChineseInputSchemeID) -> ChineseInputSchemeID {
        guard let index = available.firstIndex(where: { $0.id == current }) else {
            return defaultScheme
        }
        return available[(index + 1) % available.count].id
    }
}
