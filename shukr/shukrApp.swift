//
//  shukrApp.swift
//  shukr
//
//  Created on 8/3/24.
//

import SwiftUI
import SwiftData

@main
struct shukrApp: App {

    
    @StateObject var sharedState = SharedStateClass()
    @StateObject var prayerViewModel: PrayerViewModel // Add ViewModel here
    @State private var globalLocationManager = GlobalLocationManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SessionDataModel.self,
            MantraModel.self,
            TaskModel.self,
            DuaModel.self,
            PrayerModel.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    init() {
        let context = sharedModelContainer.mainContext
        _prayerViewModel = StateObject(wrappedValue: PrayerViewModel(context: context))
    }
    
    var body: some Scene {
        
            WindowGroup {
                NavigationView{
                    if globalLocationManager.isAuthorized{
                        // v3 mainpage - tabview paging with vertical dragging
                        TabView (selection: $sharedState.selectedViewPage){
                            // Rightmost page: History page
                            HistoryPageView()
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                .tag(0)
                                .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
                            
                            
                            // Middle page: Prayer time tracker
//                            let context = sharedModelContainer.mainContext
//                            PrayerTimesView(viewModel: PrayerViewModel(context: context))
//                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
//                                .tag(1)
//                                .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
                            
                            
                            // Middle page: Prayer time tracker
                            PrayerTimesView()
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                .tag(1)
                                .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.

                            
                            
                            // Leftmost page: Dua page
                            DuaPageView()
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                .tag(2)
                                .toolbar(.hidden, for: .tabBar) /// <-- Hiding the TabBar for a ProfileView.
                            
                            
                        }
                        .tabViewStyle(DefaultTabViewStyle()) // for testing
                    }
                    else{
                        ZStack{
                            Color.red.opacity(0.001)
                                .edgesIgnoringSafeArea(.all)
                            CircularProgressView(progress: 0)
                            Text("shukr")
                                .font(.headline)
                                .fontWeight(.thin)
                                .fontDesign(.rounded)
                        }
                        VStack{
                            Spacer()
                            Text("gimme your location bruh...")
                                .padding()
                        }
                    }
                }
            }
            .modelContainer(sharedModelContainer)
            .environment(globalLocationManager)
            .environmentObject(sharedState) // Inject shared state into the environment (Global access point for `sharedState`)
            .environmentObject(prayerViewModel) // Inject PrayerViewModel
            // Inject `sharedState` as an EnvironmentObject at the top level of the app.
            // This makes `sharedState` globally accessible to any view within the view hierarchy
            // that starts from `PrayerTimesView`.
            // All subviews can access it implicitly by declaring
            // `@EnvironmentObject var sharedState: SharedStateClass`.
            // NOTE: This injection covers all views in the hierarchy. Additional injections are unnecessary,
            // unless a view is presented outside this hierarchy, like with a new window or distinct view instance.

    }
}

//import SwiftUI

//struct SwipeNavView: View {
//    @EnvironmentObject var sharedState: SharedStateClass
//    @SceneStorage("selectedPage") private var selectedPage: Int = 1 // Persist selected page
//    
//    var body: some View {
//        ScrollViewReader { proxy in
//            ScrollView(.horizontal) {
//                LazyHStack(spacing: 0) {
//                    ForEach(0..<3) { index in
//                        Group {
//                            switch index {
//                            case 0:
//                                HistoryPageView()
//                                    .id(index)
//                            case 1:
//                                PrayerTimesView()
//                                    .id(index)
//                            case 2:
//                                DuaPageView()
//                                    .id(index)
//                            default:
////                                EmptyView()
//                                
//                                    Rectangle()
//                                        .fill(Color(hue: Double(index) / 10, saturation: 0.5, brightness: 0.8).gradient)
//                                        .overlay(
//                                            Text("\(index)").foregroundColor(.black)
//                                        )
//                                        .frame(width: UIScreen.main.bounds.width) // Adjust the frame to match the screen width
//                                        .id(index)
//                                        .containerRelativeFrame(.horizontal, alignment: .center)
//                                
//                            }
//                        }
//                        .containerRelativeFrame(.horizontal, alignment: .center)
//                    }
//                }
//            }
//            .scrollDismissesKeyboard(.immediately)
////            .ignoresSafeArea()
//            .scrollTargetLayout()
//            .scrollTargetBehavior(.paging)
////            .scrollBounceBehavior(.basedOnSize)
//            .defaultScrollAnchor(.center) // this we will show the middle of the tab view on load.
//            .scrollIndicators(.never)
//            .scrollPosition(id: .init(get: {
//                selectedPage
//            }, set: { newPosition in
//                if let newPos = newPosition {
//                    print("was \(selectedPage) and now is \(newPos)")
//                    selectedPage = newPos
//                    sharedState.selectedViewPage = newPos
//                }
//            }))
//            .onAppear {
//                UIScrollView.appearance().bounces = false
//            }
//        }
//    }
//}

// Preview provider
//struct SwipeNavView_Previews: PreviewProvider {
//    static var previews: some View {
//        SwipeNavView()
//            .environmentObject(SharedStateClass())
//            .environment(\.colorScheme, .dark)
//    }
//}
