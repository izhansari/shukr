

import SwiftUI

struct Old_TasbeehCountView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

// OG one
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//
//        var body: some View {
//            ZStack {
//                HStack(spacing: 5) {
//                    let circlesCount = tasbeeh / 100
//                    ForEach(0..<circlesCount, id: \.self) { _ in
//                        Circle()
//                            .fill(Color.gray.opacity(0.5))
//                            .frame(width: 10, height: 10)
//                    }
//                }
//                .offset(y: 40) // Position the circles below the text
//
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//            }
//        }
//    }

// PERFECT BUT only half circle arc
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // Arc of circles representing tasbeeh count / 100
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//                    ForEach(0..<circlesCount, id: \.self) { index in
//                        Circle()
//                            .fill(Color.gray.opacity(0.5))
//                            .frame(width: circleSize, height: circleSize)
//                            .position(arcPosition(for: index, totalCircles: circlesCount, center: center))
//                    }
//                }
//                .frame(height: 80) // Control the arc height
//            }
//        }
//
//        // Function to calculate the position of each circle in the arc
//        func arcPosition(for index: Int, totalCircles: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForCircle(at: index, totalCircles: totalCircles)
//            let x = center.x + arcRadius * cos(angle)
//            let y = center.y + arcRadius * sin(angle)
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle of each circle along the arc (spans π to 0 for ⏡)
//        func angleForCircle(at index: Int, totalCircles: Int) -> CGFloat {
//            let totalAngle: CGFloat = .pi // 180 degrees arc
//            let startAngle: CGFloat = .pi // Start from the bottom (⏡ shape)
//            let stepAngle = totalAngle / CGFloat(totalCircles + 1)
//            return startAngle - (stepAngle * CGFloat(index + 1))
//        }
//    }

// clock style. 12
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    ForEach(0..<min(circlesCount, 12), id: \.self) { index in
//                        Circle()
//                            .fill(Color.gray.opacity(0.5))
//                            .frame(width: circleSize, height: circleSize)
//                            .position(clockPosition(for: index, center: center))
//                    }
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (1 to 12 o'clock)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (1 o'clock to 12 o'clock)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 12 // Divide the circle into 12 positions (like a clock)
//            let startAngle: CGFloat = -.pi / 2 // Start at 12 o'clock position (top center)
//            return startAngle + stepAngle * CGFloat(index)
//        }
//    }

// backwards from 6 oclock
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    ForEach(0..<min(circlesCount, 12), id: \.self) { index in
//                        Circle()
//                            .fill(Color.gray.opacity(0.5))
//                            .frame(width: circleSize, height: circleSize)
//                            .position(clockPosition(for: index, center: center))
//                    }
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (starting from 6 o'clock)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 12 // Divide the circle into 12 positions (like a clock)
//            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
//            return startAngle - stepAngle * CGFloat(index)
//        }
//    }

// PERFECT but 12 hands
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    ZStack {
//                        ForEach(0..<min(circlesCount, 12), id: \.self) { index in
//                            Circle()
//                                .fill(Color.gray.opacity(0.5))
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: index, center: center))
//                        }
//                    }
//                    // Only apply rotation after the first circle is added
//                    .rotationEffect(.degrees(tasbeeh >= 200 ? 15 * Double(tasbeeh / 100 - 1) : 0)) //**** Rotate after first circle
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (starting from 6 o'clock)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 12 // Divide the circle into 12 positions (like a clock)
//            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
//            return startAngle - stepAngle * CGFloat(index)
//        }
//    }

// made it 10 hands
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    ZStack {
//                        ForEach(0..<min(circlesCount, 10), id: \.self) { index in
//                            Circle()
//                                .fill(Color.gray.opacity(0.5))
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: index, center: center))
//                        }
//                    }
//                    // Only apply rotation after the first circle is added
//                    .rotationEffect(.degrees(tasbeeh >= 200 ? 18 * Double(tasbeeh / 100 - 1) : 0)) //**** Rotate after first circle
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (now with 10 hands)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward, now with 10 even spots)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 10 // Divide the circle into 10 positions (like a clock with 10 hands)
//            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
//            return startAngle - stepAngle * CGFloat(index)
//        }
//    }

// YES. added purple at the top. but no reset
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        @State private var rotationAngle: Double = 0 // State variable to handle rotation animation
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    if(circlesCount >= 10 ){ // this will persist once we get more than 10. butt need to make it animate so cant have it as an if statement. or else it wont animate.
//                        ZStack{
//                            Circle()
//                                .fill(Color.purple)
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: 5, center: center)) // the top position
//                            //this will not rotate with the rest of them.
//                            // need to make it animate on show.
//                            Text("\(circlesCount/10)")
//                                .foregroundStyle(.white)
//                                .font(.footnote)
//                                .position(clockPosition(for: 5, center: center)) // the top position
//                        }
//                    }
//
//                    ZStack {
//                        ForEach(0..<min(circlesCount, 10), id: \.self) { index in
//                            Circle()
//                                .fill(index != 9 ? Color.gray.opacity(0.5) : Color.clear)
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: index, center: center))
//                        }
//                    }
//                    .rotationEffect(.degrees(rotationAngle)) // Use the animated rotation angle
//                    .onChange(of: circlesCount) {oldValue, newValue in // Trigger animation when tasbeeh changes
//                        withAnimation(.easeInOut(duration: 0.5)) {
//                            if circlesCount >= 2 && circlesCount < 10 {
//                                rotationAngle = Double(18 * (circlesCount - 1)) // Rotate by 18 degrees for each circle added after the first
//                                print(Double(18 * (circlesCount - 1)))
//                                print("#: \(Double((circlesCount - 1)))")
//
//                            } else if (circlesCount == 10) {
//                                rotationAngle = 144
//                            } else{
//                                rotationAngle = 0
//                                print("back \(circlesCount)")
//                            }
//                        }
//                    }
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (now with 10 hands)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward, now with 10 even spots)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 10 // Divide the circle into 10 positions (like a clock with 10 hands)
//            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
//            return startAngle - stepAngle * CGFloat(index)
//        }
//    }

// BET! Got it to reset. Keeps one purp at the top for 1k. put a number on it.
//    struct TasbeehCountView: View {
//        let tasbeeh: Int
//        let circleSize: CGFloat = 10 // Circle size
//        let arcRadius: CGFloat = 40 // Distance of the circles from the number (radius of the arc)
//
//        @State private var rotationAngle: Double = 0 // State variable to handle rotation animation
////        @State private var showPurpleCircle: Bool = false // State to track if the purple circle is shown
////        @State private var justReached10: Bool = false
//        private var justReachedToA1000: Bool{
//            tasbeeh % 1000 == 0 ? true : false
//        }
//        private var showPurpleCircle: Bool{
//            tasbeeh >= 1000 ? true : false
//        }
//
//        var body: some View {
//            ZStack {
//                // Display the number in the center
//                Text("\(tasbeeh % 100)")
//                    .font(.largeTitle)
//                    .bold()
//                    .fontDesign(.rounded)
//
//                // GeometryReader to help position circles
//                GeometryReader { geometry in
//                    let circlesCount = tasbeeh / 100
//                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
//
//                    // Animate the purple circle when it appears
////                    if showPurpleCircle || circlesCount >= 10 {
//                        ZStack {
//                            Circle()
//                                .fill(Color.purple)
//                                .stroke(.white, style: .init())
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: 5, center: center)) // the top position
//                            Text("\(circlesCount / 10)")
//                                .foregroundStyle(.white)
//                                .bold()
//                                .fontDesign(.rounded)
//                                .position(clockPosition(for: 5, center: center)) // the top position
//                        }
//                        .opacity(showPurpleCircle ? 1 : 0)
////                        .transition(.scale)
//                        .animation(.easeInOut(duration: 0.5), value: showPurpleCircle)
////                    }
//
//                    // Add grey circles in a clock pattern for 1-9 tasbeehs
//                    ZStack {
//                        ForEach(0..<max(circlesCount % 10, justReachedToA1000 ? 9 : 0), id: \.self) { index in
//                            Circle()
//                                .fill(Color.gray.opacity(0.5))
//                                .frame(width: circleSize, height: circleSize)
//                                .position(clockPosition(for: index, center: center))
//                                .opacity(justReachedToA1000 ? 0 : 1)
//                                .animation(.easeInOut(duration: 0.5), value: justReachedToA1000)
//                        }
//                    }
//                    .rotationEffect(.degrees(rotationAngle)) // Rotate based on tasbeeh count
//                    .onChange(of: circlesCount % 10) { oldValue, newValue in
//                        withAnimation(.easeInOut(duration: 0.5)) {
//                            if newValue > 1 && newValue % 10 != 0 {
//                                // Rotate for every 2–9 circles, omit rotation for the first one
//                                rotationAngle = Double(18 * (newValue - 1)) //**** Rotate by 18 degrees
//                                print("1: \(newValue) and \(justReachedToA1000)")
//                            } else if newValue == 0 && tasbeeh >= 1000{
//                                // Show purple circle without rotation
////                                showPurpleCircle = true
////                                justReached10 = true
//                                print("2: \(newValue) and \(justReachedToA1000)")
//                            }
//                            else if newValue == 1{
//                                rotationAngle = 0 // reset rotation to start again
////                                justReached10 = false
//                                print("3: \(newValue) and \(justReachedToA1000)")
//                            }
//                        }
//                    }
//                }
//                .frame(height: 100) // Adjust frame height to ensure there's enough space
//            }
//        }
//
//        // Function to calculate the position of each circle like clock positions (now with 10 hands)
//        func clockPosition(for index: Int, center: CGPoint) -> CGPoint {
//            let angle = angleForClockPosition(at: index)
//            let x = center.x + arcRadius * cos(angle) // X position using cosine
//            let y = center.y + arcRadius * sin(angle) // Y position using sine
//            return CGPoint(x: x, y: y)
//        }
//
//        // Function to calculate the angle corresponding to the clock positions (starting from 6 o'clock and going backward, now with 10 even spots)
//        func angleForClockPosition(at index: Int) -> CGFloat {
//            let stepAngle: CGFloat = 2 * .pi / 10 // Divide the circle into 10 positions (like a clock with 10 hands)
//            let startAngle: CGFloat = .pi / 2 // Start at 6 o'clock position (bottom center)
//            return startAngle - stepAngle * CGFloat(index)
//        }
//    }



//#Preview {
//    Old_TasbeehCountView()
//}
