//
//  NavLinkAlternativeExample.swift
//  shukr
//
//  Created by Izhan S Ansari on 10/5/24.
//


import SwiftUI
import SwiftData

struct NavLinkAlternativeExample: View {
    @State private var isDetailViewActive: Bool = false

    var body: some View {

        ZStack {
//            NavigationView {
                VStack {
                    Button(action: {
                        withAnimation {
                            isDetailViewActive.toggle()
                        }
                    }) {
                        Text("Go to Detail View")
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .navigationTitle("Home")
                }
//            }
            .zIndex(0)

            if isDetailViewActive {
                DetailView(isDetailViewActive: $isDetailViewActive)
                    .transition(.move(edge: .leading))
                    .zIndex(1)
            }
        }
    }
}

struct DetailView: View {
    @Binding var isDetailViewActive: Bool

    var body: some View {
        VStack {
            Text("Detail View")
                .font(.largeTitle)
                .padding()

            Button(action: {
                withAnimation {
                    isDetailViewActive = false
                }
            }) {
                Text("Go Back")
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue)
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    NavLinkAlternativeExample()
}
