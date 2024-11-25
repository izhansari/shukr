//
//  SeeAllPrayers.swift
//  shukr
//
//  Created on 11/23/24.
//

import SwiftUI
import SwiftData

struct SeeAllPrayers: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var context
    @State private var prayers: [PrayerModel] = []
    @State private var sortOption: SortOption = .byStartTimeAscending

    enum SortOption: String, CaseIterable {
        case byStartTimeAscending = "Start Time (Asc)"
        case byStartTimeDescending = "Start Time (Desc)"
        case byEndTimeAscending = "End Time (Asc)"
        case byEndTimeDescending = "End Time (Desc)"
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "arrow.left")
                            .font(.title2)
                            .padding()
                            .foregroundColor(.blue)
                    }
                    
                    Text("See All Prayers")
                        .font(.headline)
                        .fontDesign(.rounded)
                        .fontWeight(.medium)
                        .padding(.leading, -10)
                    Spacer()
                }
                .padding(.vertical)

                Text("Total Prayers: \(prayers.count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)

                Picker("Sort By", selection: $sortOption) {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: sortOption){ _, newValue in
                    sortPrayers()
                }

                List {
                    ForEach(prayers, id: \.id) { prayer in
                        VStack(alignment: .leading, spacing: 8) {
                            // Main Header
                            Text(prayer.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 2)

                            // Subheader
                            Text("\(formattedDate(prayer.startTime)) - \(formattedDate(prayer.endTime))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            // Divider for Completed Stats
                            
                                Divider()
                                HStack{
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Debug Info:")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.red)
                                        
                                        Text("Date At Make:")
                                        Text("\(formattedDate(prayer.dateAtMake))")
                                        Text("Latitude: \(prayer.latPrayedAt?.description ?? "N/A")")
                                        Text("Longitude: \(prayer.longPrayedAt?.description ?? "N/A")")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    if prayer.isCompleted {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Performance:")
                                                .font(.caption)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.blue)
                                            
                                            if let timeAtComplete = prayer.timeAtComplete {
                                                Text("Completed At:")
                                                Text("\(formattedDate(timeAtComplete))")
                                            }
                                            if let numberScore = prayer.numberScore {
                                                Text("Score: \(numberScore, specifier: "%.2f")")
                                            }
                                            if let englishScore = prayer.englishScore {
                                                Text("Performance: \(englishScore)")
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(.inset)
            }
            .onAppear(perform: loadPrayers)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Helper Functions
    private func loadPrayers() {
        do {
            let fetchDescriptor = FetchDescriptor<PrayerModel>(
                sortBy: [SortDescriptor(\.startTime, order: .forward)]
            )
            prayers = try context.fetch(fetchDescriptor)
            sortPrayers()
        } catch {
            print("❌ Failed to fetch prayers: \(error.localizedDescription)")
        }
        
        //// ok so quick notes I'm trying to see if I can use a stay variable and upload that with context inside of prayer times view on a pier and I'm referencing this code here so I wanna look at this study this and take it back to prayer times to do it on pier
    }

    private func sortPrayers() {
        switch sortOption {
        case .byStartTimeAscending:
            prayers.sort { $0.startTime < $1.startTime }
        case .byStartTimeDescending:
            prayers.sort { $0.startTime > $1.startTime }
        case .byEndTimeAscending:
            prayers.sort { $0.endTime < $1.endTime }
        case .byEndTimeDescending:
            prayers.sort { $0.endTime > $1.endTime }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    SeeAllPrayers()
        .modelContainer(for: PrayerModel.self, inMemory: true)
}
