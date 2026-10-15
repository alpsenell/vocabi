import SwiftUI

/// Explains how to add the widget and what slots are.
struct WidgetHelpCard: View {
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Label("Add the widget", systemImage: "rectangle.grid.2x2.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Touch and hold an empty area of your home screen until the apps jiggle.")
                    step(2, "Tap the + button in the top corner and search for Vocabi.")
                    step(3, "Choose a size and tap Add Widget.")
                }
                Divider()
                Label {
                    Text("Using several widgets? Touch and hold a widget, tap Edit Widget and give each one a different slot (1–6). Each slot shows a different word, so you never see the same word twice.")
                } icon: {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Color.accentColor)
                }
                .font(.subheadline)
            } else {
                Text("Learn passively from your home screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number, format: .number)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            Text(text).font(.subheadline)
        }
    }
}
