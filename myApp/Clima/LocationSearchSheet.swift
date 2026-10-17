//
//  LocationSearchSheet.swift
//  Clima
//

import MapKit
import SwiftUI

/// The sheet the header's arrow opens: type a place, pick it, and the screen shows its
/// weather. "Current Location" sits at the top, always, as the way back.
///
/// It only reports the choice through `onSelect` — saving it and fetching the weather is
/// the screen's job, the same as for any other reading.
struct LocationSearchSheet: View {
    /// What's chosen now, so its row can carry the tick. Nil is the current location.
    let current: ChosenPlace?
    /// Called with the picked place, or nil for "Current Location". The sheet closes
    /// itself afterwards.
    let onSelect: (ChosenPlace?) -> Void

    @State private var search = LocationSearch()
    /// The suggestion whose coordinates are being looked up, so its row can show that.
    @State private var resolving: MKLocalSearchCompletion?
    /// Set when that lookup fails, shown above the results.
    @State private var errorMessage: String?
    /// The last few places chosen, newest first — see `ChosenPlace.recents`. Copied in
    /// when the sheet opens so a swipe to remove one updates the list straight away.
    @State private var recents = ChosenPlace.recents

    @Environment(\.dismiss) private var dismiss
    @Environment(\.deviceScale) private var deviceScale

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "Current Location", subtitle: nil, systemImage: "location.fill",
                        isChosen: current == nil) {
                        choose(nil)
                    }
                }

                // Out of the way while searching: then the list is the search's.
                if !recents.isEmpty, !isSearching {
                    Section {
                        ForEach(recents, id: \.self) { place in
                            row(title: place.searchTitle ?? place.name, subtitle: place.searchSubtitle,
                                systemImage: "clock",
                                isChosen: current.map { $0.isSame(as: place) } ?? false) {
                                choose(place)
                            }
                            .swipeActions {
                                Button("Remove", systemImage: "trash", role: .destructive) {
                                    remove(place)
                                }
                            }
                        }
                    } header: {
                        Text("Recent")
                            .climaCaps(.small)
                            .foregroundStyle(Theme.inkMuted)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(Theme.valueFont(scale: deviceScale))
                            .foregroundStyle(Theme.inkMuted)
                            .listRowBackground(Theme.panel)
                    }
                }

                if !search.results.isEmpty {
                    Section {
                        ForEach(search.results, id: \.self) { completion in
                            row(title: completion.title, subtitle: completion.subtitle,
                                systemImage: nil, isChosen: false,
                                isLoading: resolving == completion) {
                                Task { await pick(completion) }
                            }
                        }
                    }
                } else if isSearching, !search.isWaiting {
                    Section {
                        Text("No matches")
                            .font(Theme.valueFont(scale: deviceScale))
                            .foregroundStyle(Theme.inkMuted)
                            .listRowBackground(Theme.panel)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.canvas)
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $search.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "City or ZIP code"
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Whether anything's been typed — the results, not the recent places, are shown then.
    private var isSearching: Bool {
        !search.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Takes a place off the recent list, here and in what's saved. If it's the place in
    /// use, it stays in use; it just stops being listed.
    private func remove(_ place: ChosenPlace) {
        recents.removeAll { $0.isSame(as: place) }
        ChosenPlace.recents = recents
    }

    /// One tappable line: an optional icon, the name, what's under it, and a tick or a
    /// spinner at the end.
    private func row(
        title: String,
        subtitle: String?,
        systemImage: String?,
        isChosen: Bool,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10 * deviceScale) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.inkMuted)
                }
                VStack(alignment: .leading, spacing: 2 * deviceScale) {
                    Text(title)
                        .font(Theme.valueFont(scale: deviceScale))
                        .foregroundStyle(Theme.ink)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.valueFont(scale: deviceScale * 0.85))
                            .foregroundStyle(Theme.inkMuted)
                    }
                }
                Spacer()
                if isLoading {
                    ProgressView()
                } else if isChosen {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.indexMark)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(resolving != nil)
        .listRowBackground(Theme.panel)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    /// Looks up the suggestion's coordinates and, if that works, chooses it.
    private func pick(_ completion: MKLocalSearchCompletion) async {
        resolving = completion
        errorMessage = nil
        defer { resolving = nil }
        do {
            choose(try await search.resolve(completion))
        } catch {
            print("Couldn't look up \(completion.title): \(error)")
            errorMessage = "Couldn't find that place. Try another."
        }
    }

    private func choose(_ place: ChosenPlace?) {
        onSelect(place)
        dismiss()
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            LocationSearchSheet(current: nil) { _ in }
        }
}
