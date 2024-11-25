//
//  NeumorphicButtonExperiment.swift
//  shukr
//
//  Created on 11/20/24.
//

import SwiftUI
import Adhan

struct PrayerButton: View {
    @EnvironmentObject var sharedState: SharedStateClass
//    @EnvironmentObject var globalLocationManager: GlobalLocationManager
    @AppStorage("calculationMethod") var calculationMethod: Int = 4
    @AppStorage("school") var school: Int = 0
    @State private var prayerTimesForDateDict:  [String : Date] = [:]

    @Binding var showChainZikrButton: Bool
    @State private var toggledText: Bool = false
    let prayer: PrayerModel
    let toggleCompletion: () -> Void
    let viewModel: PrayerViewModel
    
    private var isFuturePrayer: Bool {
        prayer.startTime > Date()
    }
    
    // Status Circle Properties
    private var statusImageName: String {
        if isFuturePrayer { return "circle" }
        return prayer.isCompleted ? "checkmark.circle.fill" : "circle"
    }
    
    private var statusColor: Color {
        if isFuturePrayer { return Color.secondary.opacity(0.2) }
        return prayer.isCompleted ? viewModel.getColorForPrayerScore(prayer.numberScore) : Color.secondary.opacity(0.5)
    }
    
    // Text Properties
    private var statusBasedOpacity: Double {
        if isFuturePrayer { return 0.6 }
        return prayer.isCompleted ? 0.7 : 1
    }
    
    // Background Properties
    private var backgroundColor: Color {
        if isFuturePrayer { return Color("bgColor") }
        return prayer.isCompleted ? Color("NeuClickedButton") : Color("bgColor")
    }
    
    // Shadow Properties
    private var shadowXOffset: CGFloat {
        prayer.isCompleted ? -2 : 0
    }
    
    private var shadowYOffset: CGFloat {
        prayer.isCompleted ? -2 : 0
    }
    
    private var nameFontSize: Font {
        return .callout
    }
    
    private var timeFontSize: Font {
        return .footnote
    }
    
    var body: some View {
        Button(action: {
            // Handle Future Prayer Toggle
            if isFuturePrayer {
                withAnimation {
                    toggledText.toggle()
                }
            } else {
                // Handle Prayer Completion with Spring Animation
                withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                    toggleCompletion()
                }
                
                // Show Chain Zikr Button Animation
                if prayer.isCompleted {
                    withAnimation {
                        showChainZikrButton = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            showChainZikrButton = false
                        }
                    }
                }
            }
        }) {
            HStack {
                // Status Circle
                Image(systemName: statusImageName)
                    .foregroundColor(statusColor)
                    .frame(width: 24, height: 24, alignment: .leading)
                
                // Prayer Name Label
                Text(prayer.name)
                    .font(nameFontSize)
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    .fontDesign(.rounded)
                    .fontWeight(.light)
                
                Spacer()
                
                // Time Display Section
                if isFuturePrayer {
                    // Future Prayer: Toggleable Time/Countdown
                    ExternalToggleText(
                        originalText: formatTimeNoSeconds(prayer.startTime),
                        toggledText: timeUntilStart(prayer.startTime),
                        externalTrigger: $toggledText,
                        font: timeFontSize,
                        fontDesign: .rounded,
                        fontWeight: .light,
                        hapticFeedback: true
                    )
                    .foregroundColor(.secondary.opacity(statusBasedOpacity))

                } else if prayer.isCompleted {
                    // Completed Prayer: Show Completion Time
                    if let completedTime = prayer.timeAtComplete {
                        Text("@ \(formatTimeNoSeconds(completedTime))")
                            .font(timeFontSize)
                            .foregroundColor(.secondary.opacity(statusBasedOpacity))
                    }
                } else {
                    // Current Prayer: Show Start Time
                    Text(formatTimeNoSeconds(prayer.startTime))
                        .font(timeFontSize)
                        .foregroundColor(.secondary)
                        .fontDesign(.rounded)
                        .fontWeight(.light)
                }
                
                // Chevron Arrow
                ChevronTap()
                    .opacity(statusBasedOpacity)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            // Background Effects Container
            .background(
                Group {
                    if isFuturePrayer || !prayer.isCompleted {
                        // Plain Effect: Future Prayer (No Shadow) or Current
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor)
                    } else {
                        // Neumorphic Effect: Completed Prayer
                        RoundedRectangle(cornerRadius: 13)
                            .fill(backgroundColor
                                // Indent/Outdent Effects
                                .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 1, x: -shadowXOffset, y: -shadowYOffset))
                                .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 1, x: shadowXOffset, y: shadowYOffset))
                            )
                        
                    }
                }
            )
            .animation(.spring(response: 0.1, dampingFraction: 0.7), value: prayer.isCompleted)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func calculatePrayerTimes(for day: Date) {
        // Map calculationMethod and school to Adhan enums
        let settingsCalculationMethod = /*getCalcMethodFromSettings()*/ getCalcMethodFromAppStorageVar()
        let settingsMadhab = /*getSchoolFromSettings()*/ getSchoolFromAppStorageVar()
        
        guard let calculationMethod = settingsCalculationMethod, let madhab = settingsMadhab else {
            print("Invalid calculation method or madhab")
            return
        }
        
        // Set up Adhan parameters
        let lat = sharedState.lastKnownLocation?.coordinate.latitude ?? 0
        let long = sharedState.lastKnownLocation?.coordinate.longitude ?? 0
        let coordinates = Coordinates(latitude: lat, longitude: long)
        var params = calculationMethod.params
        params.madhab = madhab

        // Use the selected date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: day)

        if let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
            prayerTimesForDateDict = [
                "Fajr": times.fajr,
                "Sunrise": times.sunrise,
                "Zuhr": times.dhuhr,
                "Asr": times.asr,
                "Maghrib": times.maghrib,
                "Isha": times.isha
            ]
        }
    }
}

struct ChevronTap: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .foregroundColor(.gray)
            .onTapGesture {
                triggerSomeVibration(type: .medium)
                print("chevy hit")
            }
    }
}

struct NeumorphicBorder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(Color("bgColor")
                .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 3, x: 5, y: 5))
                .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 3, x: -5, y: -5))
            )
            .shadow(color: Color("NeuDarkShad").opacity(0.5), radius: 6, x: 5, y: 5)
            .shadow(color: Color("NeuLightShad").opacity(0.5), radius: 6, x: -5, y: -5)
    }
}

struct NeumorphicProgressRing: View{
    let progress: Double
    
    var body: some View {
        
        Circle()
            .trim(from: 0,
                  to: CGFloat(progress)
            )
            .stroke(style: StrokeStyle(
                lineWidth: 10,
                lineCap: .round
            ))
            .fill(
//                .red
                Color("bgColor")
                //indent
//                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
//                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
            )
            //outdented
            .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
            .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
            .frame(width: 200, height: 200)
            .rotationEffect(.degrees(-90))
    }

}

struct NeumorphicProgressRing2: View{
    let progress: Double
    
    var body: some View {
        ZStack{
            
            Circle()
                .trim(from: 0,
                      to: CGFloat(progress)
                )
                .stroke(style: StrokeStyle(
                    lineWidth: 14,
                    lineCap: .round
                ))
                .fill(
                    .green
//                    Color("bgColor")
                    //indent
                    //                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                    //                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                )
            //outdented
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .opacity(0.5)
            
            Circle()
                .trim(from: 0,
                      to: CGFloat(progress)
                )
                .stroke(style: StrokeStyle(
                    lineWidth: 10,
                    lineCap: .round
                ))
                .fill(
                    //                .red
                    Color("bgColor")
                    //indent
                                        .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                                        .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                )
            //outdented
//                .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
//                .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
            

        }
    }

}

#Preview {
    @Previewable @State var progress: Double = 0.5
    
    ZStack {
        Color("bgColor")
            .ignoresSafeArea()
        
        VStack(spacing: 16) {
            
            NeumorphicProgressRing2(progress: progress)

            
            NeumorphicProgressRing(progress: progress)
                        
            
            Circle()
                .trim(from: 0,
                      to: CGFloat(1)
                )
                .stroke(style: StrokeStyle(
                    lineWidth: 10,
                    lineCap: .round
                ))
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                )
                .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                .frame(width: 200, height: 200)
            
            // Inner shadow implementation
            Circle()
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                )
                .frame(width: 7, height: 7)
            
        }
        .padding()
    }
}


struct NeumorphicBead: View {
    var body: some View {
//        Circle()
//            .fill(Color("bgColor")
//                .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
//                .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
//            )
//            .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
//            .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
//            .frame(width: 7, height: 7)
        Circle()
            .fill(Color("bgColor")
                .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
            )
            .frame(width: 7, height: 7)
    }
}


#Preview {
    @Previewable @State var dummyBool: Bool = true
//    @Previewable @StateObject var dummyViewModel = PrayerViewModel()


    let now = Date()
    let calendar = Calendar.current
    let previewFajr: PrayerModel = PrayerModel(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -60*60*3, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now)
    let previewZuhr: PrayerModel = PrayerModel(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now)
    
    ZStack {
        Color("bgColor")
            .ignoresSafeArea()
        
        VStack(spacing: 16) {
//            PressedPrayerButton(title: "Fajr", time: "5:36") {
//                print("Fajr tapped")
//            }
//            ClickedPrayerButton(prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
//            
//            ClickablePrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
            
//            PrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
            
            // Inner shadow implementation
            RoundedRectangle(cornerRadius: 0)
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                )
                .frame(width: 200, height: 100)
            
            // Drop shadow implementation
            RoundedRectangle(cornerRadius: 0)
                .fill(Color("bgColor"))
                .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                .frame(width: 200, height: 100)
            
            // Both together
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                )
                .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                .frame(width: 200, height: 100)
            
            // Both together inverted
            RoundedRectangle(cornerRadius: 10)
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5))
                )
                .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                .frame(width: 200, height: 100)
            
            Circle()
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                )
                .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                .frame(width: 7, height: 7)
            
            // Inner shadow implementation
            Circle()
                .fill(Color("bgColor")
                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                )
                .frame(width: 7, height: 7)
            
        }
        .padding()
    }
}


// Iterations of How I got to the above Prayer Button Design
//
//struct ClickedPrayerButton: View {
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        Button(action:
//                toggleCompletion
//        )
//        {
//            HStack {
//                Image(systemName: "checkmark.circle.fill")
//                    .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
//                    .frame(width: 24, height: 24, alignment: .leading)
//
//                Text(prayer.name)
//                    .font(.headline)
//                    .foregroundColor(.secondary).opacity(0.8)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//
//
//                Spacer()
//
//                if let completedTime = prayer.timeAtComplete {
//                    Text("@ \(formatTimeNoSeconds(completedTime))")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary).opacity(0.8)
//                }
//                else{
//                    Text("@ 00:00 PM")
//                        .font(.subheadline)
//                        .foregroundColor(.secondary).opacity(0.8)
//                }
//
//                ChevronTap().opacity(0.8)
//            }
//
//            .padding(.horizontal)
//            .padding(.vertical, 8)
//            .background(
//                RoundedRectangle(cornerRadius: 16)
//                    .fill(Color("NeuClickedButton"))
//                    .shadow(color: Color("NeuDarkShad"), radius: 2, x: -4, y: -4)
//                    .shadow(color: Color("NeuLightShad"), radius: 2, x: 4, y: 4)
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//}
//
//struct ClickablePrayerButton: View {
//    @Binding var showChainZikrButton: Bool
//    let prayer: Prayer
//    let toggleCompletion: () -> Void
//    let viewModel: PrayerViewModel
//
//    var body: some View {
//        Button(action: {
//            toggleCompletion()
//            withAnimation{
//                showChainZikrButton = true
//                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
//                    showChainZikrButton = false
//                }
//            }
//        })
//        {
//            HStack {
//                Image(systemName: "circle")
//                    .foregroundColor(Color.secondary.opacity(0.5))
//                    .frame(width: 24, height: 24, alignment: .leading)
//
//                Text(prayer.name)
//                    .font(.headline)
//                    .foregroundColor(.secondary)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//
//                Spacer()
//
//                Text(formatTimeNoSeconds(prayer.startTime))
//                    .font(.subheadline)
//                    .foregroundColor(.secondary)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//
//
//                ChevronTap()
//
//            }
//            .padding(.horizontal)
//            .padding(.vertical, 8)
//            .background(
//                RoundedRectangle(cornerRadius: 16)
//                    .fill(Color("bgColor"))
//                    .shadow(color: Color("NeuDarkShad"), radius: 2, x: 4, y: 4)
//                    .shadow(color: Color("NeuLightShad"), radius: 2, x: -4, y: -4)
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//}
//
//struct UnclickablePrayerButton: View {
//    @State private var toggledText: Bool = false
//    let prayer: Prayer
//
//    var body: some View {
//
//        Button(action: {
//            withAnimation{
//                toggledText.toggle()
//            }
//        })
//        {
//            HStack {
//                Image(systemName: "circle")
//                    .foregroundColor(Color.secondary.opacity(0.2))
//                    .frame(width: 24, height: 24, alignment: .leading)
//
//                Text(prayer.name)
//                    .font(.headline)
//                    .foregroundColor(.secondary)
//                    .fontDesign(.rounded)
//                    .fontWeight(.light)
//
//
//                Spacer()
//
//                ExternalToggleText(originalText: formatTimeNoSeconds(prayer.startTime), toggledText: timeUntilStart(prayer.startTime), externalTrigger: $toggledText , font: .subheadline, fontDesign: .rounded, fontWeight: .light, hapticFeedback: true)
//                    .foregroundColor(.secondary)
//
//
//                ChevronTap()
//
//            }
//            .padding(.horizontal)
//            .padding(.vertical, 8)
//            .background(
//                RoundedRectangle(cornerRadius: 16)
//                    .fill(Color("bgColor"))
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//}


























/*
 //
 //  NeumorphicButtonExperiment.swift
 //  shukr
 //
 //  Created on 11/20/24.
 //

 import SwiftUI
 import Adhan

 struct PrayerButton: View {
     @EnvironmentObject var sharedState: SharedStateClass
     @AppStorage("calculationMethod") var calculationMethod: Int = 4
     @AppStorage("school") var school: Int = 0

     @Binding var showChainZikrButton: Bool
     @State private var toggledText: Bool = false
     @State private var prayerTimesForDateDict:  [String : Date]
     let prayer: PrayerModel
     let toggleCompletion: () -> Void
     let viewModel: PrayerViewModel
     
     
     private var isFuturePrayer: Bool {
         prayer.startTime > Date()
     }
     
     // Status Circle Properties
     private var statusImageName: String {
         if isFuturePrayer { return "circle" }
         return prayer.isCompleted ? "checkmark.circle.fill" : "circle"
     }
     
     private var statusColor: Color {
         if isFuturePrayer { return Color.secondary.opacity(0.2) }
         return prayer.isCompleted ? viewModel.getColorForPrayerScore(prayer.numberScore) : Color.secondary.opacity(0.5)
     }
     
     // Text Properties
     private var statusBasedOpacity: Double {
         if isFuturePrayer { return 0.6 }
         return prayer.isCompleted ? 0.7 : 1
     }
     
     // Background Properties
     private var backgroundColor: Color {
         if isFuturePrayer { return Color("bgColor") }
         return prayer.isCompleted ? Color("NeuClickedButton") : Color("bgColor")
     }
     
     // Shadow Properties
     private var shadowXOffset: CGFloat {
         prayer.isCompleted ? -2 : 0
     }
     
     private var shadowYOffset: CGFloat {
         prayer.isCompleted ? -2 : 0
     }
     
     private var nameFontSize: Font {
         return .callout
     }
     
     private var timeFontSize: Font {
         return .footnote
     }
     
     var body: some View {
         Button(action: {
             // Handle Future Prayer Toggle
             if isFuturePrayer {
                 withAnimation {
                     toggledText.toggle()
                 }
             } else {
                 // Handle Prayer Completion with Spring Animation
                 withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                     toggleCompletion()
                 }
                 
                 // Show Chain Zikr Button Animation
                 if prayer.isCompleted {
                     withAnimation {
                         showChainZikrButton = true
                         DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                             showChainZikrButton = false
                         }
                     }
                 }
             }
         }) {
             HStack {
                 // Status Circle
                 Image(systemName: statusImageName)
                     .foregroundColor(statusColor)
                     .frame(width: 24, height: 24, alignment: .leading)
                 
                 // Prayer Name Label
                 Text(prayer.name)
                     .font(nameFontSize)
                     .foregroundColor(.secondary.opacity(statusBasedOpacity))
                     .fontDesign(.rounded)
                     .fontWeight(.light)
                 
                 Spacer()
                 
                 // Time Display Section
                 if isFuturePrayer {
                     // Future Prayer: Toggleable Time/Countdown
                     ExternalToggleText(
                         originalText: formatTimeNoSeconds(prayer.startTime),
                         toggledText: timeUntilStart(prayer.startTime),
                         externalTrigger: $toggledText,
                         font: timeFontSize,
                         fontDesign: .rounded,
                         fontWeight: .light,
                         hapticFeedback: true
                     )
                     .foregroundColor(.secondary.opacity(statusBasedOpacity))

                 } else if prayer.isCompleted {
                     // Completed Prayer: Show Completion Time
                     if let completedTime = prayer.timeAtComplete {
                         Text("@ \(formatTimeNoSeconds(completedTime))")
                             .font(timeFontSize)
                             .foregroundColor(.secondary.opacity(statusBasedOpacity))
                     }
                 } else {
                     // Current Prayer: Show Start Time
                     Text(formatTimeNoSeconds(prayer.startTime))
                         .font(timeFontSize)
                         .foregroundColor(.secondary)
                         .fontDesign(.rounded)
                         .fontWeight(.light)
                 }
                 
                 // Chevron Arrow
                 ChevronTap()
                     .opacity(statusBasedOpacity)
             }
             .padding(.horizontal)
             .padding(.vertical, 12)
             // Background Effects Container
             .background(
                 Group {
                     if isFuturePrayer || !prayer.isCompleted {
                         // Plain Effect: Future Prayer (No Shadow) or Current
                         RoundedRectangle(cornerRadius: 13)
                             .fill(backgroundColor)
                     } else {
                         // Neumorphic Effect: Completed Prayer
                         RoundedRectangle(cornerRadius: 13)
                             .fill(backgroundColor
                                 // Indent/Outdent Effects
                                 .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 1, x: -shadowXOffset, y: -shadowYOffset))
                                 .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 1, x: shadowXOffset, y: shadowYOffset))
                             )
                         
                     }
                 }
             )
             .animation(.spring(response: 0.1, dampingFraction: 0.7), value: prayer.isCompleted)
         }
         .buttonStyle(PlainButtonStyle())
     }
     
     private func calculatePrayerTimes(for day: Date) {
         // Map calculationMethod and school to Adhan enums
         let settingsCalculationMethod = /*getCalcMethodFromSettings()*/ getCalcMethodFromAppStorageVar()
         let settingsMadhab = /*getSchoolFromSettings()*/ getSchoolFromAppStorageVar()
         
         guard let calculationMethod = settingsCalculationMethod, let madhab = settingsMadhab else {
             print("Invalid calculation method or madhab")
             return
         }
         
         // Set up Adhan parameters
         let lat = sharedState.lastKnownLocation?.coordinate.latitude ?? 0
         let long = sharedState.lastKnownLocation?.coordinate.longitude ?? 0
         let coordinates = Coordinates(latitude: lat, longitude: long)
         var params = calculationMethod.params
         params.madhab = madhab

         // Use the selected date
         let calendar = Calendar.current
         let components = calendar.dateComponents([.year, .month, .day], from: day)

         if let times = PrayerTimes(coordinates: coordinates, date: components, calculationParameters: params) {
             prayerTimesForDateDict = [
                 "Fajr": times.fajr,
                 "Sunrise": times.sunrise,
                 "Zuhr": times.dhuhr,
                 "Asr": times.asr,
                 "Maghrib": times.maghrib,
                 "Isha": times.isha
             ]
         }
     }
 }

 struct ChevronTap: View {
     var body: some View {
         Image(systemName: "chevron.right")
             .foregroundColor(.gray)
             .onTapGesture {
                 triggerSomeVibration(type: .medium)
                 print("chevy hit")
             }
     }
 }

 struct NeumorphicBorder: View {
     var body: some View {
         RoundedRectangle(cornerRadius: 20)
             .fill(Color("bgColor")
                 .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 3, x: 5, y: 5))
                 .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 3, x: -5, y: -5))
             )
             .shadow(color: Color("NeuDarkShad").opacity(0.5), radius: 6, x: 5, y: 5)
             .shadow(color: Color("NeuLightShad").opacity(0.5), radius: 6, x: -5, y: -5)
     }
 }

 struct NeumorphicProgressRing: View{
     let progress: Double
     
     var body: some View {
         
         Circle()
             .trim(from: 0,
                   to: CGFloat(progress)
             )
             .stroke(style: StrokeStyle(
                 lineWidth: 10,
                 lineCap: .round
             ))
             .fill(
 //                .red
                 Color("bgColor")
                 //indent
 //                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
 //                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
             )
             //outdented
             .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
             .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
             .frame(width: 200, height: 200)
             .rotationEffect(.degrees(-90))
     }

 }

 struct NeumorphicProgressRing2: View{
     let progress: Double
     
     var body: some View {
         ZStack{
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(progress)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 14,
                     lineCap: .round
                 ))
                 .fill(
                     .green
 //                    Color("bgColor")
                     //indent
                     //                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                     //                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                 )
             //outdented
                 .frame(width: 200, height: 200)
                 .rotationEffect(.degrees(-90))
                 .opacity(0.5)
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(progress)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 10,
                     lineCap: .round
                 ))
                 .fill(
                     //                .red
                     Color("bgColor")
                     //indent
                                         .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                                         .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                 )
             //outdented
 //                .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
 //                .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
                 .frame(width: 200, height: 200)
                 .rotationEffect(.degrees(-90))
             

         }
     }

 }

 #Preview {
     @Previewable @State var progress: Double = 0.5
     
     ZStack {
         Color("bgColor")
             .ignoresSafeArea()
         
         VStack(spacing: 16) {
             
             NeumorphicProgressRing2(progress: progress)

             
             NeumorphicProgressRing(progress: progress)
                         
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(1)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 10,
                     lineCap: .round
                 ))
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                 .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                 .frame(width: 200, height: 200)
             
             // Inner shadow implementation
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                 )
                 .frame(width: 7, height: 7)
             
         }
         .padding()
     }
 }


 struct NeumorphicBead: View {
     var body: some View {
 //        Circle()
 //            .fill(Color("bgColor")
 //                .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
 //                .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
 //            )
 //            .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
 //            .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
 //            .frame(width: 7, height: 7)
         Circle()
             .fill(Color("bgColor")
                 .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                 .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
             )
             .frame(width: 7, height: 7)
     }
 }


 #Preview {
     @Previewable @State var dummyBool: Bool = true
 //    @Previewable @StateObject var dummyViewModel = PrayerViewModel()


     let now = Date()
     let calendar = Calendar.current
     let previewFajr: PrayerModel = PrayerModel(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -60*60*3, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now)
     let previewZuhr: PrayerModel = PrayerModel(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now)
     
     ZStack {
         Color("bgColor")
             .ignoresSafeArea()
         
         VStack(spacing: 16) {
 //            PressedPrayerButton(title: "Fajr", time: "5:36") {
 //                print("Fajr tapped")
 //            }
 //            ClickedPrayerButton(prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
 //
 //            ClickablePrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
             
 //            PrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
             
             // Inner shadow implementation
             RoundedRectangle(cornerRadius: 0)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                 )
                 .frame(width: 200, height: 100)
             
             // Drop shadow implementation
             RoundedRectangle(cornerRadius: 0)
                 .fill(Color("bgColor"))
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             // Both together
             RoundedRectangle(cornerRadius: 10)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             // Both together inverted
             RoundedRectangle(cornerRadius: 10)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                 .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                 .frame(width: 7, height: 7)
             
             // Inner shadow implementation
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                 )
                 .frame(width: 7, height: 7)
             
         }
         .padding()
     }
 }


 // Iterations of How I got to the above Prayer Button Design
 //
 //struct ClickedPrayerButton: View {
 //    let prayer: Prayer
 //    let toggleCompletion: () -> Void
 //    let viewModel: PrayerViewModel
 //
 //    var body: some View {
 //        Button(action:
 //                toggleCompletion
 //        )
 //        {
 //            HStack {
 //                Image(systemName: "checkmark.circle.fill")
 //                    .foregroundColor(viewModel.getColorForPrayerScore(prayer.numberScore))
 //                    .frame(width: 24, height: 24, alignment: .leading)
 //
 //                Text(prayer.name)
 //                    .font(.headline)
 //                    .foregroundColor(.secondary).opacity(0.8)
 //                    .fontDesign(.rounded)
 //                    .fontWeight(.light)
 //
 //
 //                Spacer()
 //
 //                if let completedTime = prayer.timeAtComplete {
 //                    Text("@ \(formatTimeNoSeconds(completedTime))")
 //                        .font(.subheadline)
 //                        .foregroundColor(.secondary).opacity(0.8)
 //                }
 //                else{
 //                    Text("@ 00:00 PM")
 //                        .font(.subheadline)
 //                        .foregroundColor(.secondary).opacity(0.8)
 //                }
 //
 //                ChevronTap().opacity(0.8)
 //            }
 //
 //            .padding(.horizontal)
 //            .padding(.vertical, 8)
 //            .background(
 //                RoundedRectangle(cornerRadius: 16)
 //                    .fill(Color("NeuClickedButton"))
 //                    .shadow(color: Color("NeuDarkShad"), radius: 2, x: -4, y: -4)
 //                    .shadow(color: Color("NeuLightShad"), radius: 2, x: 4, y: 4)
 //            )
 //        }
 //        .buttonStyle(PlainButtonStyle())
 //    }
 //}
 //
 //struct ClickablePrayerButton: View {
 //    @Binding var showChainZikrButton: Bool
 //    let prayer: Prayer
 //    let toggleCompletion: () -> Void
 //    let viewModel: PrayerViewModel
 //
 //    var body: some View {
 //        Button(action: {
 //            toggleCompletion()
 //            withAnimation{
 //                showChainZikrButton = true
 //                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
 //                    showChainZikrButton = false
 //                }
 //            }
 //        })
 //        {
 //            HStack {
 //                Image(systemName: "circle")
 //                    .foregroundColor(Color.secondary.opacity(0.5))
 //                    .frame(width: 24, height: 24, alignment: .leading)
 //
 //                Text(prayer.name)
 //                    .font(.headline)
 //                    .foregroundColor(.secondary)
 //                    .fontDesign(.rounded)
 //                    .fontWeight(.light)
 //
 //                Spacer()
 //
 //                Text(formatTimeNoSeconds(prayer.startTime))
 //                    .font(.subheadline)
 //                    .foregroundColor(.secondary)
 //                    .fontDesign(.rounded)
 //                    .fontWeight(.light)
 //
 //
 //                ChevronTap()
 //
 //            }
 //            .padding(.horizontal)
 //            .padding(.vertical, 8)
 //            .background(
 //                RoundedRectangle(cornerRadius: 16)
 //                    .fill(Color("bgColor"))
 //                    .shadow(color: Color("NeuDarkShad"), radius: 2, x: 4, y: 4)
 //                    .shadow(color: Color("NeuLightShad"), radius: 2, x: -4, y: -4)
 //            )
 //        }
 //        .buttonStyle(PlainButtonStyle())
 //    }
 //}
 //
 //struct UnclickablePrayerButton: View {
 //    @State private var toggledText: Bool = false
 //    let prayer: Prayer
 //
 //    var body: some View {
 //
 //        Button(action: {
 //            withAnimation{
 //                toggledText.toggle()
 //            }
 //        })
 //        {
 //            HStack {
 //                Image(systemName: "circle")
 //                    .foregroundColor(Color.secondary.opacity(0.2))
 //                    .frame(width: 24, height: 24, alignment: .leading)
 //
 //                Text(prayer.name)
 //                    .font(.headline)
 //                    .foregroundColor(.secondary)
 //                    .fontDesign(.rounded)
 //                    .fontWeight(.light)
 //
 //
 //                Spacer()
 //
 //                ExternalToggleText(originalText: formatTimeNoSeconds(prayer.startTime), toggledText: timeUntilStart(prayer.startTime), externalTrigger: $toggledText , font: .subheadline, fontDesign: .rounded, fontWeight: .light, hapticFeedback: true)
 //                    .foregroundColor(.secondary)
 //
 //
 //                ChevronTap()
 //
 //            }
 //            .padding(.horizontal)
 //            .padding(.vertical, 8)
 //            .background(
 //                RoundedRectangle(cornerRadius: 16)
 //                    .fill(Color("bgColor"))
 //            )
 //        }
 //        .buttonStyle(PlainButtonStyle())
 //    }
 //}

 */




//working one
/*
 import SwiftUI

 struct PrayerButton: View {
     @Binding var showChainZikrButton: Bool
     @State private var toggledText: Bool = false
     let prayer: PrayerModel
     let toggleCompletion: () -> Void
     let viewModel: PrayerViewModel
     
     private var isFuturePrayer: Bool {
         prayer.startTime > Date()
     }
     
     // Status Circle Properties
     private var statusImageName: String {
         if isFuturePrayer { return "circle" }
         return prayer.isCompleted ? "checkmark.circle.fill" : "circle"
     }
     
     private var statusColor: Color {
         if isFuturePrayer { return Color.secondary.opacity(0.2) }
         return prayer.isCompleted ? viewModel.getColorForPrayerScore(prayer.numberScore) : Color.secondary.opacity(0.5)
     }
     
     // Text Properties
     private var statusBasedOpacity: Double {
         if isFuturePrayer { return 0.6 }
         return prayer.isCompleted ? 0.7 : 1
     }
     
     // Background Properties
     private var backgroundColor: Color {
         if isFuturePrayer { return Color("bgColor") }
         return prayer.isCompleted ? Color("NeuClickedButton") : Color("bgColor")
     }
     
     // Shadow Properties
     private var shadowXOffset: CGFloat {
         prayer.isCompleted ? -2 : 0
     }
     
     private var shadowYOffset: CGFloat {
         prayer.isCompleted ? -2 : 0
     }
     
     private var nameFontSize: Font {
         return .callout
     }
     
     private var timeFontSize: Font {
         return .footnote
     }
     
     var body: some View {
         Button(action: {
             // Handle Future Prayer Toggle
             if isFuturePrayer {
                 withAnimation {
                     toggledText.toggle()
                 }
             } else {
                 // Handle Prayer Completion with Spring Animation
                 withAnimation(.spring(response: 0.1, dampingFraction: 0.7)) {
                     toggleCompletion()
                 }
                 
                 // Show Chain Zikr Button Animation
                 if prayer.isCompleted {
                     withAnimation {
                         showChainZikrButton = true
                         DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                             showChainZikrButton = false
                         }
                     }
                 }
             }
         }) {
             HStack {
                 // Status Circle
                 Image(systemName: statusImageName)
                     .foregroundColor(statusColor)
                     .frame(width: 24, height: 24, alignment: .leading)
                 
                 // Prayer Name Label
                 Text(prayer.name)
                     .font(nameFontSize)
                     .foregroundColor(.secondary.opacity(statusBasedOpacity))
                     .fontDesign(.rounded)
                     .fontWeight(.light)
                 
                 Spacer()
                 
                 // Time Display Section
                 if isFuturePrayer {
                     // Future Prayer: Toggleable Time/Countdown
                     ExternalToggleText(
                         originalText: formatTimeNoSeconds(prayer.startTime),
                         toggledText: timeUntilStart(prayer.startTime),
                         externalTrigger: $toggledText,
                         font: timeFontSize,
                         fontDesign: .rounded,
                         fontWeight: .light,
                         hapticFeedback: true
                     )
                     .foregroundColor(.secondary.opacity(statusBasedOpacity))

                 } else if prayer.isCompleted {
                     // Completed Prayer: Show Completion Time
                     if let completedTime = prayer.timeAtComplete {
                         Text("@ \(formatTimeNoSeconds(completedTime))")
                             .font(timeFontSize)
                             .foregroundColor(.secondary.opacity(statusBasedOpacity))
                     }
                 } else {
                     // Current Prayer: Show Start Time
                     Text(formatTimeNoSeconds(prayer.startTime))
                         .font(timeFontSize)
                         .foregroundColor(.secondary)
                         .fontDesign(.rounded)
                         .fontWeight(.light)
                 }
                 
                 // Chevron Arrow
                 ChevronTap()
                     .opacity(statusBasedOpacity)
             }
             .padding(.horizontal)
             .padding(.vertical, 12)
             // Background Effects Container
             .background(
                 Group {
                     if isFuturePrayer || !prayer.isCompleted {
                         // Plain Effect: Future Prayer (No Shadow) or Current
                         RoundedRectangle(cornerRadius: 13)
                             .fill(backgroundColor)
                     } else {
                         // Neumorphic Effect: Completed Prayer
                         RoundedRectangle(cornerRadius: 13)
                             .fill(backgroundColor
                                 // Indent/Outdent Effects
                                 .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 1, x: -shadowXOffset, y: -shadowYOffset))
                                 .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 1, x: shadowXOffset, y: shadowYOffset))
                             )
                         
                     }
                 }
             )
             .animation(.spring(response: 0.1, dampingFraction: 0.7), value: prayer.isCompleted)
         }
         .buttonStyle(PlainButtonStyle())
     }
 }

 struct ChevronTap: View {
     var body: some View {
         Image(systemName: "chevron.right")
             .foregroundColor(.gray)
             .onTapGesture {
                 triggerSomeVibration(type: .medium)
                 print("chevy hit")
             }
     }
 }

 struct NeumorphicBorder: View {
     var body: some View {
         RoundedRectangle(cornerRadius: 20)
             .fill(Color("bgColor")
                 .shadow(.inner(color: Color("NeuDarkShad").opacity(0.5), radius: 3, x: 5, y: 5))
                 .shadow(.inner(color: Color("NeuLightShad").opacity(0.5), radius: 3, x: -5, y: -5))
             )
             .shadow(color: Color("NeuDarkShad").opacity(0.5), radius: 6, x: 5, y: 5)
             .shadow(color: Color("NeuLightShad").opacity(0.5), radius: 6, x: -5, y: -5)
     }
 }

 struct NeumorphicProgressRing: View{
     let progress: Double
     
     var body: some View {
         
         Circle()
             .trim(from: 0,
                   to: CGFloat(progress)
             )
             .stroke(style: StrokeStyle(
                 lineWidth: 10,
                 lineCap: .round
             ))
             .fill(
 //                .red
                 Color("bgColor")
                 //indent
 //                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
 //                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
             )
             //outdented
             .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
             .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
             .frame(width: 200, height: 200)
             .rotationEffect(.degrees(-90))
     }

 }

 struct NeumorphicProgressRing2: View{
     let progress: Double
     
     var body: some View {
         ZStack{
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(progress)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 14,
                     lineCap: .round
                 ))
                 .fill(
                     .green
 //                    Color("bgColor")
                     //indent
                     //                    .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                     //                    .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                 )
             //outdented
                 .frame(width: 200, height: 200)
                 .rotationEffect(.degrees(-90))
                 .opacity(0.5)
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(progress)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 10,
                     lineCap: .round
                 ))
                 .fill(
                     //                .red
                     Color("bgColor")
                     //indent
                                         .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1))
                                         .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1))
                 )
             //outdented
 //                .shadow(color: Color("NeuDarkShad"), radius: 1, x: -1, y: 1)
 //                .shadow(color: Color("NeuLightShad"), radius: 1, x: 1, y: -1)
                 .frame(width: 200, height: 200)
                 .rotationEffect(.degrees(-90))
             

         }
     }

 }

 #Preview {
     @Previewable @State var progress: Double = 0.5
     
     ZStack {
         Color("bgColor")
             .ignoresSafeArea()
         
         VStack(spacing: 16) {
             
             NeumorphicProgressRing2(progress: progress)

             
             NeumorphicProgressRing(progress: progress)
                         
             
             Circle()
                 .trim(from: 0,
                       to: CGFloat(1)
                 )
                 .stroke(style: StrokeStyle(
                     lineWidth: 10,
                     lineCap: .round
                 ))
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                 .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                 .frame(width: 200, height: 200)
             
             // Inner shadow implementation
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                 )
                 .frame(width: 7, height: 7)
             
         }
         .padding()
     }
 }


 struct NeumorphicBead: View {
     var body: some View {
 //        Circle()
 //            .fill(Color("bgColor")
 //                .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
 //                .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
 //            )
 //            .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
 //            .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
 //            .frame(width: 7, height: 7)
         Circle()
             .fill(Color("bgColor")
                 .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                 .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
             )
             .frame(width: 7, height: 7)
     }
 }


 #Preview {
     @Previewable @State var dummyBool: Bool = true
 //    @Previewable @StateObject var dummyViewModel = PrayerViewModel()


     let now = Date()
     let calendar = Calendar.current
     let previewFajr: PrayerModel = PrayerModel(name: "Fajr", startTime: calendar.date(byAdding: .second, value: -60*60*3, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now)
     let previewZuhr: PrayerModel = PrayerModel(name: "Dhuhr", startTime: calendar.date(byAdding: .second, value: 7, to: now) ?? now, endTime: calendar.date(byAdding: .second, value: 40, to: now) ?? now)
     
     ZStack {
         Color("bgColor")
             .ignoresSafeArea()
         
         VStack(spacing: 16) {
 //            PressedPrayerButton(title: "Fajr", time: "5:36") {
 //                print("Fajr tapped")
 //            }
 //            ClickedPrayerButton(prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
 //
 //            ClickablePrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
             
 //            PrayerButton(showChainZikrButton: $dummyBool, prayer: previewFajr, toggleCompletion: {}, viewModel: dummyViewModel)
             
             // Inner shadow implementation
             RoundedRectangle(cornerRadius: 0)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                 )
                 .frame(width: 200, height: 100)
             
             // Drop shadow implementation
             RoundedRectangle(cornerRadius: 0)
                 .fill(Color("bgColor"))
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             // Both together
             RoundedRectangle(cornerRadius: 10)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: -5, y: -5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: 5, y: 5))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             // Both together inverted
             RoundedRectangle(cornerRadius: 10)
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 3, x: 5, y: 5)
                 .shadow(color: Color("NeuLightShad"), radius: 3, x: -5, y: -5)
                 .frame(width: 200, height: 100)
             
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1))
                 )
                 .shadow(color: Color("NeuDarkShad"), radius: 1, x: 1, y: 1)
                 .shadow(color: Color("NeuLightShad"), radius: 1, x: -1, y: -1)
                 .frame(width: 7, height: 7)
             
             // Inner shadow implementation
             Circle()
                 .fill(Color("bgColor")
                     .shadow(.inner(color: Color("NeuDarkShad"), radius: 1, x: -1, y: -1))
                     .shadow(.inner(color: Color("NeuLightShad"), radius: 1, x: 1, y: 1))
                 )
                 .frame(width: 7, height: 7)
             
         }
         .padding()
     }
 }
 */
