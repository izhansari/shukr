//
//  AdhanTestView.swift
//  shukr
//
//  Created on 11/23/24.
//

import SwiftUI
import Adhan

struct AdhanTestView: View {
    @State private var prayerTimes: PrayerTimes?
    @State private var currentPrayer: Prayer?
    @State private var nextPrayer: Prayer?
    @State private var prayerTimesArray: [(String, Date)] = []
    @State private var location: (latitude: Double, longitude: Double) = (35.78947, -78.78117) // Default coordinates
    @State private var cityName: String = "Raleigh, NC"
    @State private var calculationMethod: CalculationMethod = .northAmerica
    @State private var madhab: Madhab = .hanafi
    @State private var selectedDate: Date = Date()
    @State private var isEditingCoordinates: Bool = false
    @State private var tempLatitude: String = ""
    @State private var tempLongitude: String = ""
    
    // Default locations
    let defaultLocations: [(name: String, latitude: Double, longitude: Double)] = [
        ("Cupertino, CA", 37.322998, -122.032182),
        ("Atlanta, GA", 33.7490, -84.3880),
        ("Las Vegas, NV", 36.1699, -115.1398),
        ("Tokyo, Japan", 35.6895, 139.6917),
        ("Cary, NC", 35.7915, -78.7811)
    ]

    var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("City: \(cityName)")
                    .font(.headline)
                HStack {
                    Text("Coordinates: \(String(format: "%.5f", location.latitude)), \(String(format: "%.5f", location.longitude))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit") {
                        isEditingCoordinates.toggle()
                        tempLatitude = "\(location.latitude)"
                        tempLongitude = "\(location.longitude)"
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.vertical)

            // Inline coordinate editor
            if isEditingCoordinates {
                VStack(spacing: 8) {
                    TextField("Latitude", text: $tempLatitude)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    TextField("Longitude", text: $tempLongitude)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)

                    List {
                        Section(header: Text("Default Locations")) {
                            ForEach(defaultLocations, id: \.name) { location in
                                Button {
                                    self.tempLatitude = "\(location.latitude)"
                                    self.tempLongitude = "\(location.longitude)"
                                    self.cityName = location.name
                                } label: {
                                    HStack {
                                        Text(location.name)
                                        Spacer()
                                        Text("\(location.latitude), \(location.longitude)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 200) // Limit height of the list

                    HStack {
                        Button("Cancel") {
                            isEditingCoordinates = false
                        }
                        .buttonStyle(.bordered)

                        Button("Save") {
                            if let lat = Double(tempLatitude), let lon = Double(tempLongitude) {
                                location = (lat, lon)
                                calculatePrayerTimes()
                                isEditingCoordinates = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.bottom)
            }

            Divider()

            // Compact date picker with chevrons
            HStack {
                Button(action: { changeDate(by: -1) }) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                Spacer()
                Text(formattedDate(selectedDate))
                    .font(.headline)
                Spacer()
                Button(action: { changeDate(by: 1) }) {
                    Image(systemName: "chevron.right")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)

            Picker("Calculation Method", selection: $calculationMethod) {
                ForEach(CalculationMethod.allCases, id: \.self) { method in
                    Text(method.rawValue.capitalized).tag(method)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
            .onChange(of: calculationMethod) { _, new in
                calculatePrayerTimes()
            }

            Picker("Madhab", selection: $madhab) {
                Text("Hanafi").tag(Madhab.hanafi)
                Text("Shafi").tag(Madhab.shafi)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: madhab) { _, new in
                calculatePrayerTimes()
            }

            Divider()

            if !prayerTimesArray.isEmpty {
                List {
                    ForEach(prayerTimesArray, id: \.0) { prayer, time in
                        VStack(alignment: .leading) {
                            Text(prayer)
                                .font(.headline)
                            Text("\(formattedTime(time))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Text("No prayer times available.").foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            calculatePrayerTimes()
        }
    }

    // MARK: - Helper Functions
    private func calculatePrayerTimes() {
        let coordinates = Coordinates(latitude: location.latitude, longitude: location.longitude)
        var params = calculationMethod.params // Dynamically update params
        params.madhab = madhab

        // Use the selected date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: selectedDate)

        if let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
            self.prayerTimes = times
            self.prayerTimesArray = [
                ("Fajr", times.fajr),
                ("Sunrise", times.sunrise),
                ("Dhuhr", times.dhuhr),
                ("Asr", times.asr),
                ("Maghrib", times.maghrib),
                ("Isha", times.isha)
            ]
            self.currentPrayer = times.currentPrayer()
            self.nextPrayer = times.nextPrayer()
        }
    }

    private func changeDate(by days: Int) {
        let calendar = Calendar.current
        if let newDate = calendar.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
            calculatePrayerTimes()
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

#Preview {
    AdhanTestView()
}


