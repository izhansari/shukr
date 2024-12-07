import SwiftUI

struct testSessionCardView: View {
    let title: String
    let sessionMode: Int // 0 for freestyle, 1 for timed, 2 for count target mode
    let totalCount: Int
    let sessionDuration: String
    let sessionTime: String
    let tasbeehRate: String
    let targetMin: Int
    let targetCount: String
    
    @Environment(\.colorScheme) var colorScheme


    var sessionModeIcon: String {
        switch sessionMode {
        case 0: return "infinity"  // Freestyle
        case 1: return "timer"     // Timed mode
        case 2: return "number"    // Count target mode
        default: return "questionmark" // Fallback
        }
    }
    
    var textForTarget: String{
        switch sessionMode {
        case 0: return ""  // Freestyle
        case 1: return "\(targetMin)m"     // Timed mode
        case 2: return targetCount    // Count target mode
        default: return "?!*" // Fallback
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Top Section: Title and Mode Icon
            HStack {
                Image(systemName: sessionModeIcon)
                    .font(.title3)
                    .foregroundColor(.gray)
                Text(sessionMode != 0 ? textForTarget : "")
                    .font(.headline)
                    .bold()
                
                Spacer()
                
                Text(title)
                    .font(.headline)
                    .bold()
            }

            // Middle Section: Count, Duration, (Optional Section)
            HStack {
                // First Section (Count)
                Text("Count: \(totalCount)")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                // Second Section (Session Duration)
                Text("Duration: \(sessionDuration)")
                    .font(.subheadline)

                Spacer()
                
                // Second Section (Session Duration)
                Text("Rate: \(tasbeehRate)")
                    .font(.subheadline)
            }
            .padding(.vertical, 5)

            // Bottom Left Section: Time
            HStack {
                Text(sessionTime)
                    .font(.footnote)
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

struct testSessionCardView2: View {
    let title: String
    let sessionMode: Int // 0 for freestyle, 1 for timed, 2 for count target mode
    let totalCount: Int
    let sessionDuration: String
    let sessionTime: String
    let tasbeehRate: String
    let targetMin: Int
    let targetCount: String
    
    @Environment(\.colorScheme) var colorScheme


    var sessionModeIcon: String {
        switch sessionMode {
        case 0: return "infinity"  // Freestyle
        case 1: return "timer"     // Timed mode
        case 2: return "number"    // Count target mode
        default: return "questionmark" // Fallback
        }
    }
    
    var textForTarget: String{
        switch sessionMode {
        case 0: return ""  // Freestyle
        case 1: return "\(targetMin)m"     // Timed mode
        case 2: return targetCount    // Count target mode
        default: return "?!*" // Fallback
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            // Top Section: Title and Mode Icon
            
            HStack {
                VStack(alignment: .leading){
                    Text(title)
                        .font(.title2)
                        .bold()
                    Text(sessionTime)
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Image(systemName: sessionModeIcon)
                    .font(.title3)
                    .foregroundColor(.gray)
                Text(sessionMode != 0 ? textForTarget : "")
                    .font(.headline)
                    .bold()
            }
            

            // Middle Section: Count, Duration, (Optional Section)
            HStack {
                Spacer()
                // First Section (Count)
                VStack{
                    Text("Count:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(totalCount)")
                        .font(.subheadline)
                }
                
                Spacer()

                // Second Section (Session Duration)
                VStack{
                    Text("Duration:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(sessionDuration)")
                        .font(.subheadline)
                }

                Spacer()
                
                // Third Section (Session Duration)
                VStack{
                    Text("Rate:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("\(tasbeehRate)")
                        .font(.subheadline)
                }
                
                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.horizontal)

            // Bottom Left Section: Time
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color.black : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}


#Preview {
    
    testSessionCardView2(
        title: "Alhamdulillah",
        sessionMode: 1,  // 1 for timed mode
        totalCount: 786,
        sessionDuration: "15m 30s",
        sessionTime: "2:30 PM",
        tasbeehRate: "1m 30s",
        targetMin: 3,
        targetCount: "786"
    )
}

