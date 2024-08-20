//
//  ContentView.swift
//  shukr
//
//  Created by Izhan S Ansari on 8/3/24.
//

import SwiftUI
import SwiftData
import WidgetKit

struct ContentView: View {
    @AppStorage("count", store: UserDefaults(suiteName: "group.betternorms.shukr.shukrWidget"))
    var tasbeeh: Int = 0
    var timerIsActive = false
    @State var selectedMinutes = 1

    var body: some View {
        Spacer()
        VStack(spacing: 40) {
            ZStack{
                Circle()
                    .stroke(lineWidth: 24)
                    .frame(width: 200, height: 200)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 10, y: 10)
                Circle()
                    .stroke(lineWidth: 0.34)
                    .frame(width: 175, height: 175)
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black.opacity(0.3), .clear]), startPoint: .bottomTrailing, endPoint: .topLeading))
                    .overlay {
                        Circle()
                            .stroke(.black.opacity(0.1), lineWidth: 2)
                            .blur(radius: 5)
                            .mask {
                                Circle()
                                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .topLeading, endPoint: .bottomTrailing))
                            }
                    }
                
                Circle()
                    .trim(from: 0, to: CGFloat(tasbeeh) / 100)
                    .stroke(style: StrokeStyle(lineWidth: 24, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.purple, .blue]), startPoint: .topLeading, endPoint: .bottomTrailing))
                    .animation(.spring(), value: tasbeeh)
                Text("\(tasbeeh)").bold().font(.largeTitle)
            }
            HStack(spacing: 60) {
                Button(action: {
                    tasbeeh = max(tasbeeh - 1, 0)
                    WidgetCenter.shared.reloadAllTimelines()
                }, label: {
                    Image(systemName: "minus").font(.title)
                })
                Button(action: {
                    tasbeeh = min(tasbeeh + 1, 100)
                    WidgetCenter.shared.reloadAllTimelines()
                }, label: {
                    Image(systemName: "plus").font(.title)
                })
            }
        }
        .font(.largeTitle)
        .padding()
        Spacer()
        HStack{
            if(!timerIsActive){
                Picker("Minutes", selection: $selectedMinutes) {
                    ForEach(1..<60) { minute in
                        Text("\(minute)m").tag(minute)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(width: 100)
                .padding()
            }
        }
    }
}


#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
        
}
