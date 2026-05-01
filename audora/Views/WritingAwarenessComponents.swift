import SwiftUI

struct WritingSurfaceCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let subtitle: String?
    let accent: LinearGradient
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        accent: LinearGradient = LinearGradient(
            colors: [Color(red: 0.16, green: 0.32, blue: 0.62), Color(red: 0.08, green: 0.13, blue: 0.26)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), lineWidth: 1)
                )
        )
        .overlay(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(accent)
                .frame(height: 4)
                .padding(.horizontal, 16)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 18, y: 10)
    }
}

struct WritingChip: View {
    let text: String
    let tone: Tone

    enum Tone {
        case neutral
        case target
        case avoid
        case success

        var foreground: Color {
            switch self {
            case .neutral: return Color.primary
            case .target: return Color(red: 0.08, green: 0.29, blue: 0.58)
            case .avoid: return Color(red: 0.6, green: 0.22, blue: 0.1)
            case .success: return Color(red: 0.1, green: 0.42, blue: 0.28)
            }
        }

        var background: Color {
            switch self {
            case .neutral: return Color.primary.opacity(0.06)
            case .target: return Color.accentColor.opacity(0.16)
            case .avoid: return Color.orange.opacity(0.18)
            case .success: return Color.green.opacity(0.18)
            }
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(tone.background)
            )
    }
}

struct WritingMetricTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}

struct WritingCanvasBackground: View {
    var body: some View {
        ZStack {
            Color(NSColor.underPageBackgroundColor)

            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.05))
                .frame(width: 420, height: 420)
                .blur(radius: 80)
                .offset(x: -180, y: -220)

            Circle()
                .fill(Color.green.opacity(0.04))
                .frame(width: 320, height: 320)
                .blur(radius: 60)
                .offset(x: 220, y: 260)
        }
        .ignoresSafeArea()
    }
}
