import SwiftUI

struct MeetingReminderView: View {
    let appName: String
    let onRecord: () -> Void
    let onIgnore: () -> Void
    let onSettings: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            // Icon or Indicator
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Circle()
                    .stroke(Color.red.opacity(0.5), lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .scaleEffect(isHovering ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isHovering)
            }
            .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting Detected")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)

                Text("in \(appName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onRecord) {
                    Text("Record")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.red)
                                .shadow(color: Color.red.opacity(0.3), radius: 4, x: 0, y: 2)
                        )
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Ignore \(appName)", action: onIgnore)
                    Button("Settings...", action: onSettings)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .frame(width: 320)
        .onAppear {
            isHovering = true
        }
    }
}

#Preview {
    MeetingReminderView(
        appName: "Zoom",
        onRecord: {},
        onIgnore: {},
        onSettings: {}
    )
    .padding()
    .background(Color.blue)
}
