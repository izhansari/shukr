//
//  CityPickerSheet.swift
//  shukr
//
//  Pick a city by name instead of sharing your location. Used from the welcome screen when
//  location is denied and from Settings > Location Information.
//

import SwiftUI
import MapKit

struct CityPickerSheet: View {
    @EnvironmentObject var envLocationManager: EnvLocationManager
    @Environment(\.dismiss) private var dismiss
    /// Called after a city is saved (the welcome screen uses it to go in).
    var onPicked: () -> Void = {}

    @State private var query = ""
    @State private var results: [CityResult] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var fieldFocused: Bool

    struct CityResult: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("City, e.g. Raleigh", text: $query)
                        .focused($fieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search(now: true) }
                } footer: {
                    Text("Prayer times, the widget and the qibla use this city. Allow location access in Settings any time to switch to your exact location.")
                }

                if searching {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if !results.isEmpty {
                    Section {
                        ForEach(results) { city in
                            Button {
                                envLocationManager.setManualLocation(city.coordinate, name: city.name)
                                dismiss()
                                onPicked()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(city.name).foregroundStyle(.primary)
                                    if !city.detail.isEmpty {
                                        Text(city.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Text("No matching cities").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Choose your city")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, _ in search(now: false) }
            .onAppear { fieldFocused = true }
        }
        .tint(.green)
    }

    /// Debounced while typing; immediate on return.
    private func search(now: Bool) {
        searchTask?.cancel()
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; searching = false; return }
        searchTask = Task {
            if !now { try? await Task.sleep(for: .milliseconds(350)) }
            guard !Task.isCancelled else { return }
            searching = results.isEmpty
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = .address
            let items = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
            guard !Task.isCancelled else { return }
            results = items.prefix(8).map(Self.result(for:))
            searching = false
        }
    }

    private static func result(for item: MKMapItem) -> CityResult {
        let placemark = item.placemark
        let name = placemark.locality ?? item.name ?? placemark.administrativeArea ?? "Unknown"
        let detail = [placemark.administrativeArea, placemark.country]
            .compactMap { $0 }
            .filter { $0 != name }
            .joined(separator: ", ")
        return CityResult(name: name, detail: detail, coordinate: placemark.coordinate)
    }
}
