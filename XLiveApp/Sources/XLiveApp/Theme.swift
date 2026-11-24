import SwiftUI

/// Stile Midas: pannello antracite, display neri con cifre ambra, REC rosso.
enum Theme {
    static let panel = Color(hex: 0x2b2d30)
    static let panelDark = Color(hex: 0x1d1f21)
    static let lcd = Color.black
    static let amber = Color(hex: 0xf2a900)
    static let rec = Color(hex: 0xc8102e)
    static let ledGreen = Color(hex: 0x3ddc84)
    static let text = Color(hex: 0xe8e8e8)
    static let dim = Color(hex: 0x8a8d91)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// Display nero con cifre ambra.
struct LCD: View {
    let label: String
    let value: String
    var size: CGFloat = 40
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
            Text(value).font(.system(size: size, weight: .medium, design: .monospaced)).foregroundStyle(Theme.amber)
                .minimumScaleFactor(0.5).lineLimit(1)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.lcd, in: RoundedRectangle(cornerRadius: 6))
    }
}

struct PanelButton: View {
    let title: String
    var fill: Color = Theme.panelDark
    var textColor: Color = Theme.text
    var height: CGFloat = 64
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(textColor)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(fill, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.12), lineWidth: 1))
                .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

func formatClock(ms: Int) -> String {
    let s = max(0, ms) / 1000
    return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
}
