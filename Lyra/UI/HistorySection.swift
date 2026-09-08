import SwiftUI

struct HistorySection: View {
    @ObservedObject private var store = HistoryStore.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 14) {
            // Search
            SettingsCard(colorScheme: colorScheme) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    TextField("Search history...", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                    if !store.searchQuery.isEmpty {
                        Button {
                            store.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Toolbar
            HStack {
                Text("\(store.items.count) dictations")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.items.isEmpty {
                    Button("Clear All") {
                        store.clearAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // List
            if store.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.filteredItems) { item in
                            HistoryRow(item: item, colorScheme: colorScheme)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.6))
            Text(store.searchQuery.isEmpty ? "No dictations yet" : "No matches")
                .font(.system(size: 13, weight: .medium))
            if store.searchQuery.isEmpty {
                Text("Your transcriptions will appear here after you dictate.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let colorScheme: ColorScheme

    @ObservedObject private var store = HistoryStore.shared
    @State private var isHovered = false

    var body: some View {
        SettingsCard(colorScheme: colorScheme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.text)
                        .font(.system(size: 13))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.toggleFavorite(item: item)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 13))
                            .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isFavorite ? "Remove favorite" : "Mark favorite")
                }

                HStack(spacing: 10) {
                    Label(formattedDate(item.date), systemImage: "clock")
                    Label(Language(rawValue: item.languageCode)?.displayName ?? item.languageCode, systemImage: "globe")
                    Label(item.modelName, systemImage: "cpu")

                    Spacer()

                    Button {
                        copyToPasteboard(item.text)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Copy")

                    Button {
                        store.delete(item: item)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Delete")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
