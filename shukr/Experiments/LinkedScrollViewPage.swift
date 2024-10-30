import SwiftUI

struct LinkedScrollViewPage: View {
    @State private var selectedDayIndex: Int = 0
    @State private var currentPageIndex: Int = 0
    @State private var isCalendarPresented: Bool = false

    let days = ["Today", "Yesterday", "Thu, Oct 3", "Wed, Oct 2", "Today", "Yesterday", "Thu, Oct 3", "Wed, Oct 2"]

    var body: some View {
        VStack {
            // TabView for selecting the days
            TabView(selection: $selectedDayIndex) {
                ForEach(0..<days.count, id: \ .self) { index in
                    Text(days[index])
                        .font(.system(size: 16))
                        .foregroundColor(index == selectedDayIndex ? Color.blue : Color.secondary)
                        .underline(index == selectedDayIndex)
                        .frame(height: 50) // Adjusted height to make the area shorter
                        .padding(.horizontal, 10)
                        .tag(index)
                }
            }
            .frame(height: 60) // Set the frame height to limit the overall space taken by TabView
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
//            .padding(.horizontal, 100)
            .onChange(of: selectedDayIndex, perform: { newValue in
                withAnimation {
                    currentPageIndex = newValue
                }
            })

            // TabView with paging for detailed content
            TabView(selection: $currentPageIndex) {
                ForEach(0..<days.count, id: \ .self) { index in
                    VStack {
                        Text("Details for \(days[index])")
                            .font(.largeTitle)
                        Spacer()
                    }
                    .tag(index)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemBackground))
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .onChange(of: currentPageIndex, perform: { newValue in
                withAnimation {
                    selectedDayIndex = newValue
                }
            })

            Spacer()
        }
        .sheet(isPresented: $isCalendarPresented) {
            CalendarSheetView(isPresented: $isCalendarPresented)
        }
        .navigationBarItems(trailing: Button(action: {
            isCalendarPresented = true
        }, label: {
            Image(systemName: "calendar")
        }))
    }
}

struct CalendarSheetView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack {
            Text("Calendar")
                .font(.largeTitle)
            Button("Close") {
                isPresented = false
            }
            .padding()
        }
    }
}

struct LinkedScrollViewPage_Previews: PreviewProvider {
    static var previews: some View {
        LinkedScrollViewPage()
    }
}
