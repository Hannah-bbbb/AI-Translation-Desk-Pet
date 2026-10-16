import AppKit
import SwiftUI

/// A word or short phrase the user looked up, and when to ask about it again.
struct Word: Codable, Identifiable, Equatable {
    var term: String
    var meaning: String
    var added: Date
    /// Looking a word up again means it did not stick.
    var lookups = 1
    /// Correct answers in a row. Decides how long until the next review.
    var streak = 0
    var due: Date

    var id: String { term.lowercased() }
    var isLearned: Bool { streak >= Vocabulary.intervals.count }
}

/// The words he remembers for you, reviewed at growing intervals.
@MainActor
final class Vocabulary: ObservableObject {
    /// Days until the next review, by how many times in a row the word was remembered.
    /// One more correct answer after the last interval and the word counts as learned.
    nonisolated static let intervals = [1, 3, 7, 16, 35]

    @Published private(set) var words: [Word] = []
    private let file: URL

    /// `~/Library/Application Support/Yimiao/vocabulary.json`
    nonisolated static var defaultFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Yimiao", isDirectory: true)
            .appendingPathComponent("vocabulary.json")
    }

    init(file: URL = Vocabulary.defaultFile) {
        self.file = file
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let saved = try? decoder.decode([Word].self, from: data) {
            words = saved
        }
    }

    /// Whether a selection is short enough to be vocabulary rather than a sentence to read.
    static func isWord(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        let isCJK = text.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains($0.value) || (0x3040...0x30FF).contains($0.value) || (0xAC00...0xD7AF).contains($0.value)
        }
        if isCJK { return text.count <= 8 }
        return text.count <= 40 && text.split(whereSeparator: \.isWhitespace).count <= 3
    }

    /// Returns whether the word is new to the list, rather than looked up again.
    @discardableResult
    func record(_ term: String, meaning: String, now: Date = Date()) -> Bool {
        let due = now.addingTimeInterval(Double(Self.intervals[0]) * 86400)
        defer { save() }
        if let index = words.firstIndex(where: { $0.id == term.lowercased() }) {
            words[index].meaning = meaning
            words[index].lookups += 1
            words[index].streak = 0
            words[index].due = due
            return false
        }
        words.append(Word(term: term, meaning: meaning, added: now, due: due))
        return true
    }

    /// The word that has been waiting longest for its review.
    func nextDue(now: Date = Date()) -> Word? {
        words.filter { !$0.isLearned && $0.due <= now }.min { $0.due < $1.due }
    }

    func grade(_ word: Word, remembered: Bool, now: Date = Date()) {
        guard let index = words.firstIndex(where: { $0.id == word.id }) else { return }
        words[index].streak = remembered ? word.streak + 1 : 0
        let streak = words[index].streak
        words[index].due = streak < Self.intervals.count
            ? now.addingTimeInterval(Double(Self.intervals[streak]) * 86400)
            : .distantFuture
        save()
    }

    func remove(_ word: Word) {
        words.removeAll { $0.id == word.id }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(words).write(to: file, options: .atomic)
    }
}

struct VocabularyView: View {
    @ObservedObject var vocabulary: Vocabulary

    var body: some View {
        Group {
            if vocabulary.words.isEmpty {
                ContentUnavailableView(
                    "还没有生词",
                    systemImage: "character.book.closed",
                    description: Text("选中一个单词或短语翻译后，我会记在这里，过几天来考你")
                )
            } else {
                List {
                    Section(summary) {
                        ForEach(vocabulary.words.sorted { $0.added > $1.added }) { word in
                            row(word)
                        }
                    }
                }
            }
        }
        .frame(width: 420, height: 480)
    }

    private var summary: String {
        let due = vocabulary.words.filter { !$0.isLearned && $0.due <= Date() }.count
        let learned = vocabulary.words.filter(\.isLearned).count
        return "共 \(vocabulary.words.count) 个，\(due) 个待复习，\(learned) 个已掌握"
    }

    private func row(_ word: Word) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(word.term).font(.headline)
                Text(word.meaning).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 8)
            Text(status(word)).font(.caption).foregroundStyle(.secondary)
            Button {
                vocabulary.remove(word)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("从生词本删除")
        }
        .padding(.vertical, 2)
    }

    private func status(_ word: Word) -> String {
        if word.isLearned { return "已掌握" }
        let days = Int((word.due.timeIntervalSinceNow / 86400).rounded(.up))
        return days <= 0 ? "待复习" : (days == 1 ? "明天复习" : "\(days) 天后复习")
    }
}

@MainActor
final class VocabularyWindow {
    private var window: NSWindow?

    func show(_ vocabulary: Vocabulary) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: VocabularyView(vocabulary: vocabulary)))
            window.title = "生词本"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
