import MestreCore
import SwiftUI

/// A definition laid out as cards (`dictionary.cards`): the word, then one
/// card per sense. The rows behind it are the dictionary's usual results, so Return, ⌘K and
/// the footer work as in the list.
struct DefinitionCards: View {
    let entry: DictionaryEntry
    let width: CGFloat
    let open: () -> Void
    @Environment(\.panelStyle) private var style

    private static let gap: CGFloat = 8

    var body: some View {
        let half = (width - Self.gap) / 2
        VStack(alignment: .leading, spacing: Self.gap) {
            headword
            // Pairs side by side; an odd one out takes the full width.
            ForEach(Array(stride(from: 0, to: entry.senses.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: Self.gap) {
                    senseCard(start, width: start + 1 < entry.senses.count ? half : width)
                    if start + 1 < entry.senses.count { senseCard(start + 1, width: half) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let origin = entry.origin {
                card(palette: 2) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Origin").font(style.font(11, .semibold)).textCase(style.sectionCase)
                        Text(origin).font(style.font(12)).lineLimit(2)
                    }
                }
                .frame(width: width)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    private var headword: some View {
        card(palette: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.headword)
                    .font(style.font(34, .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                HStack(spacing: 8) {
                    if let partOfSpeech = entry.partOfSpeech {
                        Text(partOfSpeech)
                            .font(style.font(12, .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(Capsule().strokeBorder(lineWidth: 1))
                    }
                    Text([entry.syllables, entry.pronunciation.map { "/\($0)/" }].compactMap { $0 }.joined(separator: "  "))
                        .font(style.font(14))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
        }
        .frame(width: width)
    }

    private func senseCard(_ index: Int, width: CGFloat) -> some View {
        let sense = entry.senses[index]
        return card(palette: 3 + index) {
            VStack(alignment: .leading, spacing: 8) {
                if entry.senses.count > 1 {
                    Text("\(index + 1)").font(style.font(12, .heavy)).opacity(0.6)
                }
                Text(sense.text)
                    .font(style.font(15, .semibold))
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                if let example = sense.example {
                    Text("“\(example)”")
                        .font(style.font(13).italic())
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
    }

    private func card(palette: Int, @ViewBuilder content: () -> some View) -> some View {
        let tile = style.tile(palette)
        return content()
            .foregroundStyle(style.ink(of: tile))
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(style.tileShape().fill(tile.fill))
    }
}
