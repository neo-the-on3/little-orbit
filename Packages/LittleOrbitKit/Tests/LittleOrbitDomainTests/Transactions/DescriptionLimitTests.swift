import Foundation
import LittleOrbitDomain
import Testing

@Suite("Description limit (D55, D105, D111)")
struct DescriptionLimitTests {
    private let a99 = String(repeating: "a", count: 99)
    private let a100 = String(repeating: "a", count: 100)

    @Test("Typing a 101st character inserts nothing and shows no note (S51)")
    func typingStops() {
        let edit = DescriptionLimit.apply(old: a100, new: a100 + "b")
        #expect(edit.text == a100)
        #expect(!edit.wasShortened)
    }

    @Test("An emoji counts as one: 99 a + 👨‍👩‍👧 fits, then b doesn't (S52)")
    func graphemes() {
        let family = "👨‍👩‍👧"
        let withEmoji = DescriptionLimit.apply(old: a99, new: a99 + family)
        #expect(withEmoji.text == a99 + family)
        #expect(withEmoji.text.count == 100)
        #expect(DescriptionLimit.apply(old: withEmoji.text, new: withEmoji.text + "b").text == a99 + family)
    }

    @Test("A 150-character paste keeps the first 100 with the note (S55, S56)")
    func pasteCut() {
        let pasted = String(repeating: "x", count: 150)
        let edit = DescriptionLimit.apply(old: "", new: pasted)
        #expect(edit.text == String(repeating: "x", count: 100))
        #expect(edit.wasShortened)
        let exact = DescriptionLimit.apply(old: "", new: a100)
        #expect(exact.text == a100 && !exact.wasShortened)
    }

    @Test("A paste in the middle keeps all existing text and cuts the paste to fit (S58)")
    func pasteAtCursor() {
        let existing = "Weekly" + String(repeating: ".", count: 74)  // 80 characters
        let pasted = String(repeating: "p", count: 50)
        let new = "Weekly" + pasted + String(repeating: ".", count: 74)
        let edit = DescriptionLimit.apply(old: existing, new: new)
        #expect(edit.text == "Weekly" + String(repeating: "p", count: 20) + String(repeating: ".", count: 74))
        #expect(edit.wasShortened)
    }

    @Test("At 100, a paste inserts nothing and still shows the note (S66)")
    func pasteWhenFull() {
        let edit = DescriptionLimit.apply(old: a100, new: a100 + "pasted")
        #expect(edit.text == a100)
        #expect(edit.wasShortened)
    }

    @Test("A cut never splits a flag or a decomposed é (S57)")
    func boundary() {
        let flags = String(repeating: "🇮🇳", count: 120)
        let edit = DescriptionLimit.apply(old: "", new: flags)
        #expect(edit.text == String(repeating: "🇮🇳", count: 100))
        let decomposed = String(repeating: "e\u{301}", count: 101)
        #expect(DescriptionLimit.apply(old: "", new: decomposed).text.count == 100)
        #expect(DescriptionLimit.apply(old: "", new: decomposed).text.unicodeScalars.last == "\u{301}")
    }

    @Test("An existing 120-character description is kept; deleting is allowed (S64, D105)")
    func existingOverLimit() {
        let long = String(repeating: "l", count: 120)
        #expect(DescriptionLimit.apply(old: long, new: long).text == long)
        #expect(DescriptionLimit.apply(old: long, new: String(long.dropLast())).text.count == 119)
        #expect(DescriptionLimit.apply(old: long, new: long + "x").text == long)
        #expect(DescriptionLimit.isOverLimit(long))
        #expect(DescriptionLimit.counter(for: long) == "120 / 100")
    }

    @Test("The counter shows from 80 characters (S70, S71, D111)")
    func counter() {
        #expect(DescriptionLimit.counter(for: String(repeating: "c", count: 79)) == nil)
        #expect(DescriptionLimit.counter(for: String(repeating: "c", count: 80)) == "80 / 100")
        #expect(DescriptionLimit.counter(for: a100) == "100 / 100")
    }

    @Test("Import shortens and flags the row for a warning (S69)")
    func importShortens() {
        let (text, wasShortened) = DescriptionLimit.shortenedForImport(String(repeating: "i", count: 130))
        #expect(text.count == 100)
        #expect(wasShortened)
        let short = DescriptionLimit.shortenedForImport("short")
        #expect(short.text == "short")
        #expect(!short.wasShortened)
    }
}
