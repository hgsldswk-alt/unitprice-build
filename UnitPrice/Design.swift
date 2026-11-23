import SwiftUI

enum Palette {
    static let paper = Color(red: 251/255, green: 248/255, blue: 242/255)
    static let card = Color(red: 255/255, green: 253/255, blue: 249/255)
    static let ink = Color(red: 32/255, green: 39/255, blue: 35/255)
    static let muted = Color(red: 86/255, green: 95/255, blue: 87/255)
    static let line = Color(red: 222/255, green: 215/255, blue: 201/255)
    static let accent = Color(red: 46/255, green: 196/255, blue: 182/255)
    static let onAccent = Color(red: 16/255, green: 48/255, blue: 44/255)
    static let highlight = Color(red: 232/255, green: 246/255, blue: 242/255)
}

struct Action: View {
    let title: String
    let id: String
    var icon: String? = nil
    var primary = false
    var fill = false
    let run: () -> Void

    var body: some View {
        Button(action: run) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).accessibilityHidden(true) }
                Text(title).multilineTextAlignment(.center)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(minWidth: 44, maxWidth: fill ? .infinity : nil, minHeight: 44)
            .contentShape(Rectangle())
            .foregroundStyle(primary ? Palette.onAccent : Palette.ink)
            .background(primary ? Palette.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

extension View {
    func ticket(fill: Color = Palette.card, stroke: Color = Palette.line, radius: CGFloat = 13) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(stroke).allowsHitTesting(false) }
    }

    func note() -> some View { font(.footnote).foregroundStyle(Palette.muted) }
}

struct SheetTitle: View {
    let title: String
    var id: String = "sheet.title"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader).accessibilityIdentifier(id)
            Spacer(minLength: 8)
            Action(title: L.t("close"), id: "sheet.close") { dismiss() }
        }
    }
}
