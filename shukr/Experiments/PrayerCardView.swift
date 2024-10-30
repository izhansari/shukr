
// MINE before GPT O1
import SwiftUI
import SwiftData

struct PrayerCardView: View {
    @Bindable var prayer: PrayerModel // Bind to the PrayerModel using @Bindable
//    @State var timeLeft: String = ""
    @State private var showUpcomingStartTimeBool: Bool = true


    struct ProgressLine: View { //line to show 2 seconds to indicate to user the card will disappear from the completed section. ideally this line is at the bottom of the card... and ideally it wouldnt fade out as it gets to full.... I only did this because it was a way for me to have it not show on completed cards.
        var progress: CGFloat
        
        var body: some View {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.gray)
                    .frame(width: geometry.size.width * progress, height: 4)
                    .opacity(progress == 1 ? 0 : 1)
            }
        }
    }
    
    var body: some View {
        //the main view of the card. its too big for my liking. Im also kinda making the view by picking and choosing based on the state as I go which probably isnt the best.
        if(prayer.prayerState == .missed){
            ZStack {
                // Background card view
                VStack {
                    Image(systemName: iconName())
                        .resizable()
                        .frame(width: 35, height: 35)
                        .foregroundColor(.gray)
//                        .padding(.bottom)

                    Text(prayer.prayerName.uppercased())
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
                .frame(width: 70, height: 120)
//                .padding()
//                .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                .background(Color.gray.opacity(0.4))
                .cornerRadius(10)

                // Top-right button
                VStack {
                    HStack {
                        Spacer() // Push button to the right
                        Button(action: {
                            if prayer.prayerState == .completed {
                                resetPrayerState()
                            } else {
                                completePrayer()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.7), lineWidth: 2)
                                    .frame(width: 16, height: 16)

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
//                                    .font(.system(size: 20))
                                    .opacity(prayer.prayerState == .completed ? 1 : 0)
                                    .scaleEffect(prayer.prayerState == .completed ? 1 : 0.1)
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.25), value: prayer.prayerState)
                    }
//                    .background(.red)
                    Spacer() // Push button to the top
                }
//                .background(.yellow)
                .frame(width: 55, height: 105)
//                .padding([.top, .trailing], 33) // Adjust padding as needed
            }
            


        }
        else if(prayer.prayerState == .completed){
            ZStack {
                // Background card view
                VStack {
                    Image(systemName: iconName())
                        .resizable()
                        .frame(width: 35, height: 35)
                        .foregroundColor(.white)
//                        .padding(.bottom)

                    Text(prayer.prayerName.uppercased())
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                    
                    if let timeAtComplete = prayer.timeAtComplete {
                        Text(shortTimeFormatter.string(from: timeAtComplete))
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 70, height: 120)
//                .padding()
//                .background(Color(red: 0.12, green: 0.12, blue: 0.12))
                .background(Color.gray)
                .cornerRadius(10)

                // Top-right button
                VStack {
                    HStack {
                        Spacer() // Push button to the right
                        Button(action: {
                            if prayer.prayerState == .completed {
                                resetPrayerState()
                            } else {
                                completePrayer()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 2)
                                    .frame(width: 16, height: 16)

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
//                                    .font(.system(size: 20))
                                    .opacity(prayer.prayerState == .completed ? 1 : 0)
                                    .scaleEffect(prayer.prayerState == .completed ? 1 : 0.1)
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.25), value: prayer.prayerState)
                    }
//                    .background(.red)
                    Spacer() // Push button to the top
                }
//                .background(.yellow)
                .frame(width: 55, height: 105)
//                .padding([.top, .trailing], 33) // Adjust padding as needed
            }
            


        }
        else{
            VStack {
                
                HStack {
                    Image(systemName: iconName())
                        .resizable()
                        .frame(width: 30, height: 30)
                        .padding()

                    VStack(alignment: .leading) {
                        HStack {
                            Text(prayer.prayerName.uppercased())
                                .font(.headline)
                        }

                        // Display the correct time based on the prayer state
                        if prayer.prayerState == .upcoming {
                            if(showUpcomingStartTimeBool){
                                Text(shortTimeFormatter.string(from: prayer.startTimeDate))
                                    .font(.title)
                                    .onTapGesture {
                                        triggerSomeVibration(type: .light)
                                        showUpcomingStartTimeBool.toggle()
                                    }
                            }
                            else{
                                Text(inMSTimeFormatter(from: prayer.startTimeDate.timeIntervalSince(Date())))
                                    .font(.title)
                                    .onTapGesture {
                                        triggerSomeVibration(type: .light)
                                        showUpcomingStartTimeBool.toggle()
                                    }
                            }

                        } else if prayer.prayerState == .current {
                            Text(mLeftTimeFormatter(from: prayer.endTimeDate.timeIntervalSince(Date())))
                                .font(.title)
                        } else if prayer.prayerState == .completed {
                            Text("\(prayer.prayerScore.rawValue)")
                                .font(.title)
                        } else if prayer.prayerState == .missed {
                            Text("Incomplete")
                                .font(.title)
                        }
                    }

                    Spacer()

                    // Button to mark as completed
                    if prayer.prayerState != .upcoming {
                        Button(action: {
                            if prayer.prayerState == .completed {
                                resetPrayerState()
                            } else {
                                completePrayer()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.gray, lineWidth: 2)
                                    .frame(width: 26, height: 26)

                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 20))
                                    .opacity(prayer.prayerState == .completed ? 1 : 0)
                                    .scaleEffect(prayer.prayerState == .completed ? 1 : 0.1)
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0.25), value: prayer.prayerState)
                    }
                }
                .padding([.leading, .bottom, .trailing])

                // Using the reusable progress bar with color transition
                
                    TimeProgressViewWithSmoothColorTransition(
                        startTime: prayer.startTimeDate,
                        endTime: prayer.endTimeDate,
                        completedTime: .constant(prayer.timeAtComplete)
                    )
                
                
//                ProgressLine(progress: prayer.prayerState == .completed ? 1 : 0)
//                    .frame(height: 2)
//                    .animation(.linear(duration: 1.9), value: prayer.prayerState)

            }
            .padding(.vertical)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .onAppear {
                updatePrayerState()
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                updatePrayerState()
            }
        }
 
    }

    // Function to update prayer state and score
    private func updatePrayerState() {
        let now = Date()

        if prayer.prayerState == .completed {
            return
        } else if now < prayer.startTimeDate {
            prayer.prayerState = .upcoming
        } else if now >= prayer.startTimeDate && now < prayer.endTimeDate {
            prayer.prayerState = .current
//            let remainingTime = prayer.endTimeDate.timeIntervalSince(now)
//            timeLeft = mLeftTimeFormatter(from: remainingTime)
        } else if now >= prayer.endTimeDate && prayer.prayerState != .completed {
            prayer.prayerState = .missed
        }
    }

    private func completePrayer() {
        prayer.prayerState = .completed
        prayer.timeAtComplete = Date()
        updatePrayerScore()
        triggerSomeVibration(type: .light)
    }


    private func resetPrayerState() {
        if(Date() > prayer.startTimeDate && Date() < prayer.endTimeDate) {
//            timeLeft = mLeftTimeFormatter(from: prayer.endTimeDate.timeIntervalSince(Date()))
            prayer.prayerState = .current
        } else if(Date() >= prayer.endTimeDate) {
            prayer.prayerState = .missed
        }

        prayer.timeAtComplete = nil
        prayer.prayerScore = .Empty
    }


    private func updatePrayerScore() {
        let totalInterval = prayer.endTimeDate.timeIntervalSince(prayer.startTimeDate)

        if let completedTime = prayer.timeAtComplete {
            let completedInterval = completedTime.timeIntervalSince(prayer.startTimeDate)
            let percentage = completedInterval / totalInterval

            if percentage >= 1 {
                prayer.prayerScore = .Kaza
            } else if percentage > 0.75 {
                prayer.prayerScore = .Poor
            } else if percentage > 0.50 {
                prayer.prayerScore = .Good
            } else if percentage > 0.00 {
                prayer.prayerScore = .Optimal
            } else {
                prayer.prayerScore = .Empty
            }
        }
    }

    // Function to determine icon based on prayer name
    private func iconName() -> String {
        switch prayer.prayerName.lowercased() {
        case "fajr":
            return "sunrise.fill"
        case "zuhr":
            return "sun.max.fill"
        case "asr":
            return "sunset.fill"
        case "maghrib":
            return "moon.fill"
        default:
            return "moon.stars.fill"
        }
    }
}









struct TodayPrayerView: View {
    @State var showCompletedPrayers = false // State to toggle the completed prayers
    @State var showCaughtUpMessage = false // State to toggle the caught up screen
    
    @State private var currentTime = Date()
    private var upcomingBool: Bool {
        prayers.contains(where: { $0.startTimeDate > currentTime || $0.timeAtComplete ?? Date() > Date().addingTimeInterval(-2) || ($0.prayerScore == .Empty && $0.prayerState != .missed) })
    }
    
    // Sample prayer models for demonstration (replace with actual data)
    var prayers: [PrayerModel]
    
    var body: some View {
        ZStack{
            VStack{
//                HStack(alignment: .top, spacing: 4) {
//                    ForEach(prayers) { prayer in
//                        VStack{
//                            let color = getColorForScore(prayerScore: prayer.prayerScore)
//                            Capsule()
//                                .fill(color)
//                                .frame(height: 8)
//                                .frame(maxWidth: .infinity)
//                            
//                            if(showCompletedPrayers){
//                                
//                                if(prayer.prayerState == .missed || prayer.prayerState == .completed) {
//                                        PrayerCardView(prayer: prayer)
//                                    }
//                            }
//                        }
//                    }
//                }
//                .padding(.horizontal)
//                .padding(.vertical, 8)
//                .onTapGesture {
//                    withAnimation {
//                        showCompletedPrayers.toggle() // Toggle showing completed prayers
//                    }
//                }
//                
//                Spacer()
                
                ScrollView {
                    
                    VStack(spacing: 10) {
                        // Upcoming and Current Prayers
                        if currentPrayers.count > 0 {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.gray)
                                .fontWeight(.medium)
                                .padding(.bottom, 5)
                            
                            ForEach(currentPrayers) { prayer in
                                PrayerCardView(prayer: prayer)
//                                    .opacity(prayer.prayerState == .current ? 1 : 0.7)
                            }
                        }
                    }
                    
                    VStack(spacing: 10) {
                        // Upcoming and Current Prayers
                        if upcomingPrayers.count > 0 {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.gray)
                                .fontWeight(.medium)
                                .padding(.bottom, 5)
                            
                            ForEach(upcomingPrayers) { prayer in
                                PrayerCardView(prayer: prayer)
//                                    .opacity(prayer.prayerState == .current ? 1 : 0.7)
                                    .opacity(0.6)
                            }
                        }
                    }
                    .padding()
                }
                .scrollIndicators(.hidden)
                .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
                    // Update current time every second
                    currentTime = Date()
                }
                
                Spacer()
                

                // Progress Bar
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(prayers) { prayer in
                        VStack{
                            if(showCompletedPrayers){
                                if(prayer.prayerState == .missed || prayer.prayerState == .completed) {
                                        PrayerCardView(prayer: prayer)
                                    }
                            }
                            let color = getColorForScore(prayerScore: prayer.prayerScore)
                            Capsule()
                                .fill(color)
                                .frame(height: 8)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .onTapGesture {
                    withAnimation {
                        showCompletedPrayers.toggle() // Toggle showing completed prayers
                    }
                }
            }
            
            if todaysCompletedPrayers.count == 5 /*todaysMissedPrayers.count == 0 && upcomingPrayers.count == 0*/ /*!upcomingBool*/{
                GeometryReader { geometry in
                    VStack{
                        Spacer()
                        Text("ٱلْحَمْدُ لِلَّٰهِ")
                            .font(.largeTitle)
                        Text("you're all caught up for today!")
                            .font(.title3)
                            .padding()
                        Spacer()
                        Text("fajr is in ???")
                        
                        Spacer()
                    }
                            
                            .frame(width: geometry.size.width, height: geometry.size.height)
//                            .background(.gray)
                            .opacity(showCaughtUpMessage ? 1 : 0)
                            .animation(.easeIn(duration: 0.5), value: showCaughtUpMessage)
//                            .onTapGesture{
//                                showCaughtUpMessage = false
//                                showCompletedPrayers = true
//                            }

                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        showCaughtUpMessage = true
                    }
                }
            }

        }
//        .navigationBarHidden(true)
    }

    
    private var todaysMissedPrayers: [PrayerModel] {
        prayers.filter {
            // is marked as missed   &&   its startTime was same as today
            $0.prayerState == .missed &&
            Calendar.current.isDate($0.startTimeDate, inSameDayAs: Date())
        }
    }
    
    
    private var upcomingPrayers: [PrayerModel] {
//        prayers.filter { $0.prayerState == .upcoming || $0.prayerState == .current }
//        prayers.filter { $0.prayerState == .upcoming || $0.prayerState == .current || $0.timeAtComplete ?? Date() > Date().addingTimeInterval(-2)}
//        prayers.filter { $0.prayerState != .missed && $0.timeAtComplete ?? Date() > currentTime.addingTimeInterval(-2) && $0.prayerScore != .Kaza}
//        prayers.filter { $0.prayerState == .current || $0.prayerState == .upcoming}
        prayers.filter { $0.prayerState == .upcoming}
    }
    
    private var currentPrayers: [PrayerModel] {
//        prayers.filter { $0.prayerState == .upcoming || $0.prayerState == .current }
//        prayers.filter { $0.prayerState == .upcoming || $0.prayerState == .current || $0.timeAtComplete ?? Date() > Date().addingTimeInterval(-2)}
//        prayers.filter { $0.prayerState != .missed && $0.timeAtComplete ?? Date() > currentTime.addingTimeInterval(-2) && $0.prayerScore != .Kaza}
        prayers.filter { $0.prayerState == .current}
    }
    
    private var todaysCompletedPrayers: [PrayerModel] {
        prayers.filter {
            // is marked as complete   &&   its startTime was same as today
            $0.prayerState == .completed &&
            Calendar.current.isDate($0.startTimeDate, inSameDayAs: Date())
        }
    }

    // Function to return the appropriate color based on prayer score
    func getColorForScore(prayerScore: PrayerModel.PrayerScoreEnum) -> Color {
        switch prayerScore {
        case .Optimal:
            return .green
        case .Good:
            return .yellow
        case .Poor:
            return .red
        case .Kaza:
            return .gray
        default:
            return .gray.opacity(0.4) // Use a light gray for empty or undefined
        }
    }
}

struct SmallPrayerView: View {
    @Bindable var prayer: PrayerModel

    var body: some View {
        VStack {
            Image(systemName: iconName())
                .resizable()
                .frame(width: 35, height: 35)
                .foregroundColor(.white)
                .padding(.bottom)

            Text(prayer.prayerName.uppercased())
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
        .frame(width: 60, height: 100)
        .padding()
        .background(Color(red: 0.31, green: 0.31, blue: 0.31))
        .cornerRadius(10)
    }

    private func iconName() -> String {
        switch prayer.prayerName.lowercased() {
        case "fajr":
            return "sunrise.fill"
        case "zuhr":
            return "sun.max.fill"
        case "asr":
            return "sunset.fill"
        case "maghrib":
            return "moon.fill"
        case "isha":
            return "moon.stars.fill"
        default:
            return "circle"
        }
    }
}

struct TimeProgressViewWithSmoothColorTransition: View {
    // Example start and end times
    let startTime: Date
    let endTime: Date
    @Binding var completedTime: Date?
    
    // Current time
    @State private var currentTime: Date = Date()
    @State private var completed: Bool = false
    
    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                // Progress bar background with dynamic gradient
                GeometryReader { geometry in
                    let progressWidth = CGFloat(progress) * geometry.size.width
                    let tickPosition = progressWidth
                    
                    // Smooth animated color
                    Capsule()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: progColor, location: colorPosition),
                                    .init(color: Color.gray.opacity(0.4), location: colorPosition+0.1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)
//                        .animation(.easeInOut(duration: 0.3), value: progColor) // Animate color transition
//                        .animation(.easeInOut(duration: 0.3), value: colorPosition)
                    
                    // Current time text under the tick
                    if(Date() >= startTime && currentTime <= endTime || completedTime != nil){
                        if completedTime ?? Date() <= endTime{
                            Text(hmmTimeFormatter.string(from: completedTime ?? Date()))
                                .foregroundColor(.primary)
                                .font(.caption)
                                .position(x: tickPosition, y: -10) // Align text with the tick mark
                            
                            // White tick mark
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: 2, height: 8)
                                .position(x: tickPosition, y: 2) // Position the tick on the progress
                        }
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal)
            .padding(.horizontal)
            .animation(.easeInOut(duration: 1), value: colorPosition)
            .animation(.easeInOut(duration: 0.3), value: progColor) // Animate color transition

            
            // Display the start and end times
            HStack {
                Text(hmmTimeFormatter.string(from: startTime))
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
                Text(hmmTimeFormatter.string(from: endTime))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal)
        }
        .onAppear {
            // Update current time when the view appears
            currentTime = Date()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            // Update current time every second
            withAnimation {
                currentTime = Date()
            }
        }
    }
    
    // Computed property to calculate progress between startTime and endTime
    private var progress: Double {
        let totalInterval = endTime.timeIntervalSince(startTime)
        let currentInterval = currentTime.timeIntervalSince(startTime)
        
        if let completedTime = completedTime {
            let completedInterval = completedTime.timeIntervalSince(startTime)
            
            if completedInterval <= 0 {
                return 0.0 // Before start time
            } else if completedInterval >= totalInterval {
                return 1.0 // After end time
            } else {
                return completedInterval / totalInterval // Between start and end times
            }
        }

        
        if currentInterval <= 0 {
            return 0.0 // Before start time
        } else if currentInterval >= totalInterval {
            return 1.0 // After end time
        } else {
            return currentInterval / totalInterval // Between start and end times
        }
    }
    
    private var colorPosition: Double {
        //this is going to return progress. But if completed, then we set to 1
        if(completedTime != nil){
            return 1
        }
        return progress
    }
    
    // Smooth color transition based on progress
    private var progColor: Color {
        if progress >= 1 && completedTime != nil{
            return Color.gray
        } else if progress >= 1 {
            return Color.gray.opacity(0.4)
        } else if progress > 0.75 {
            return Color.red
        } else if progress > 0.50 {
            return Color.yellow
        } else if progress > 0.00 {
            return Color.green
        } else {
            return Color.gray.opacity(0.4)
        }
    }
}

// Preview for the new TodayPrayerView
struct TodayPrayerView_Previews: PreviewProvider {
    static var previews: some View {
        let prayer1 = PrayerModel(
            prayerName: "FAJR",
            startTimeDate: Date().addingTimeInterval(-100),
            endTimeDate: Date().addingTimeInterval(-60)
        )
        let prayer2 = PrayerModel(
            prayerName: "ZUHR",
            startTimeDate: Date().addingTimeInterval(-600),
            endTimeDate: Date().addingTimeInterval(200)
        )
        let prayer3 = PrayerModel(
            prayerName: "ASR",
            startTimeDate: Date().addingTimeInterval(-300),
            endTimeDate: Date().addingTimeInterval(200)
        )
        let prayer4 = PrayerModel(
            prayerName: "MAGHRIB",
            startTimeDate: Date().addingTimeInterval(10),
            endTimeDate: Date().addingTimeInterval(60)
        )
        let prayer5 = PrayerModel(
            prayerName: "ISHA",
            startTimeDate: Date().addingTimeInterval(10),
            endTimeDate: Date().addingTimeInterval(80)
        )

        let prayers = [prayer1, prayer2, prayer3, prayer4, prayer5]

        TodayPrayerView(prayers: prayers)
    }
}


struct TimeProgressViewWithSmoothColorTransition_Previews: PreviewProvider {
    static var previews: some View {
        @Previewable @State var testCompletedTime: Date? = Date()
        // Example preview with specific start and end times
        TimeProgressViewWithSmoothColorTransition(startTime: Date().addingTimeInterval(-4), endTime: Date().addingTimeInterval(2), completedTime: $testCompletedTime)
    }
}



