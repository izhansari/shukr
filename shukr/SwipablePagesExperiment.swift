// SwipeExperClaude.swift
import SwiftUI

struct SwipeExperClaude: View {
    @State private var offset: CGSize = .zero
    @State private var activeEdge: Edge? = nil
    @State private var dragAxis: DragAxis? = nil
    @State private var isSwipingBack: Bool = false
    @GestureState private var dragState = DragState.inactive
    
    private let dragThreshold: CGFloat = 100
    private let springAnimation: Animation = .spring(response: 0.3, dampingFraction: 0.8)
    
    enum Edge {
        case left, right, top, bottom
        
        var isHorizontal: Bool {
            switch self {
            case .left, .right: return true
            case .top, .bottom: return false
            }
        }
    }
    
    enum DragAxis {
        case horizontal, vertical
    }
    
    enum DragState {
        case inactive
        case dragging(translation: CGSize)
        
        var translation: CGSize {
            switch self {
            case .inactive: return .zero
            case .dragging(let translation): return translation
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main content
                MainView()
                    .offset(offset)
                
                // Side pages
                Group {
                    if dragAxis == .horizontal {
                        if (activeEdge == .left && !isSwipingBack) ||
                           (activeEdge == .right && isSwipingBack) ||
                           (dragState.translation.width > 0 && !isSwipingBack) {
                            LeftPage()
                                .frame(width: geometry.size.width)
                                .offset(x: getPageOffset(for: .left, geometry: geometry))
                        }
                        
                        if (activeEdge == .right && !isSwipingBack) ||
                           (activeEdge == .left && isSwipingBack) ||
                           (dragState.translation.width < 0 && !isSwipingBack) {
                            RightPage()
                                .frame(width: geometry.size.width)
                                .offset(x: getPageOffset(for: .right, geometry: geometry))
                        }
                    } else if dragAxis == .vertical {
                        if (activeEdge == .top && !isSwipingBack) ||
                           (activeEdge == .bottom && isSwipingBack) ||
                           (dragState.translation.height > 0 && !isSwipingBack) {
                            TopPage()
                                .frame(height: geometry.size.height)
                                .offset(y: getPageOffset(for: .top, geometry: geometry))
                        }
                        
                        if (activeEdge == .bottom && !isSwipingBack) ||
                           (activeEdge == .top && isSwipingBack) ||
                           (dragState.translation.height < 0 && !isSwipingBack) {
                            BottomPage()
                                .frame(height: geometry.size.height)
                                .offset(y: getPageOffset(for: .bottom, geometry: geometry))
                        }
                    }
                }
            }
            .gesture(
                DragGesture()
                    .updating($dragState) { value, state, _ in
                        state = .dragging(translation: value.translation)
                    }
                    .onChanged { value in
                        // If we have an active edge but no drag axis, we're starting a swipe back
                        if activeEdge != nil && dragAxis == nil {
                            isSwipingBack = true
                            dragAxis = activeEdge?.isHorizontal == true ? .horizontal : .vertical
                        }
                        // If we have no active edge, we're starting a new swipe
                        else if dragAxis == nil {
                            isSwipingBack = false
                            let translation = value.translation
                            if abs(translation.width) > abs(translation.height) {
                                dragAxis = .horizontal
                                activeEdge = translation.width > 0 ? .left : .right
                            } else {
                                dragAxis = .vertical
                                activeEdge = translation.height > 0 ? .top : .bottom
                            }
                        }
                        
                        // Apply offset based on the locked drag axis
                        switch dragAxis {
                        case .horizontal:
                            offset = CGSize(width: value.translation.width, height: 0)
                        case .vertical:
                            offset = CGSize(width: 0, height: value.translation.height)
                        case .none:
                            break
                        }
                    }
                    .onEnded { value in
                        let translation = value.translation
                        let velocity = value.predictedEndTranslation.subtract(translation)
                        let shouldSnapToEdge = shouldSnapToEdge(translation: translation, velocity: velocity)
                        
                        withAnimation(springAnimation) {
                            if shouldSnapToEdge && !isSwipingBack {
                                switch activeEdge {
                                case .left:
                                    offset.width = geometry.size.width
                                case .right:
                                    offset.width = -geometry.size.width
                                case .top:
                                    offset.height = geometry.size.height
                                case .bottom:
                                    offset.height = -geometry.size.height
                                case .none:
                                    offset = .zero
                                }
                            } else {
                                offset = .zero
                                if isSwipingBack {
                                    activeEdge = nil
                                }
                            }
                            
                            if !shouldSnapToEdge {
                                dragAxis = nil
                                isSwipingBack = false
                            }
                        }
                    }
            )
        }
        .edgesIgnoringSafeArea(.all)
    }
    
    private func getPageOffset(for edge: Edge, geometry: GeometryProxy) -> CGFloat {
        switch edge {
        case .left:
            return -geometry.size.width + max(0, offset.width)
        case .right:
            return geometry.size.width + min(0, offset.width)
        case .top:
            return -geometry.size.height + max(0, offset.height)
        case .bottom:
            return geometry.size.height + min(0, offset.height)
        }
    }
    
    private func shouldSnapToEdge(translation: CGSize, velocity: CGSize) -> Bool {
        switch activeEdge {
        case .left:
            return translation.width > dragThreshold || velocity.width > 500
        case .right:
            return translation.width < -dragThreshold || velocity.width < -500
        case .top:
            return translation.height > dragThreshold || velocity.height > 500
        case .bottom:
            return translation.height < -dragThreshold || velocity.height < -500
        case .none:
            return false
        }
    }
}

// Individual page views remain the same
struct MainView: View {
    var body: some View {
        ZStack {
            Color.white
            VStack {
                Text("Main View")
                    .font(.largeTitle)
                Text("Swipe from any edge")
                    .foregroundColor(.gray)
            }
        }
    }
}

struct LeftPage: View {
    var body: some View {
        ZStack {
            Color.blue
            Text("Left Page")
                .font(.largeTitle)
                .foregroundColor(.white)
        }
    }
}

struct RightPage: View {
    var body: some View {
        ZStack {
            Color.green
            Text("Right Page")
                .font(.largeTitle)
                .foregroundColor(.white)
        }
    }
}

struct TopPage: View {
    var body: some View {
        ZStack {
            Color.orange
            Text("Top Page")
                .font(.largeTitle)
                .foregroundColor(.white)
        }
    }
}

struct BottomPage: View {
    var body: some View {
        ZStack {
            Color.purple
            Text("Bottom Page")
                .font(.largeTitle)
                .foregroundColor(.white)
        }
    }
}

// Helper extension for vector arithmetic
extension CGSize {
    func subtract(_ size: CGSize) -> CGSize {
        return CGSize(
            width: self.width - size.width,
            height: self.height - size.height
        )
    }
}

#Preview {
    SwipeExperClaude()
}
