//
//  InfoModal.swift
//  shukr
//
//  Settings' ⓘ explanations as a floating card (owner, 2026-10-12: "open like a floating modal that uses a frosted
//  background with a very transparent material … topping the background dismisses the modal and there's also like an X
//  button"). The app's own way of floating a card over a page (ZikrCardEditor over the pause screen): a clear,
//  unanimated full-screen cover, a light frost over the page that fades in (`LightFrost`), the card easing up and in.
//

import SwiftUI

extension View {
    /// The ⓘ's explanation as a floating card over a light frost; a tap on the page around it or its ✕ closes it.
    /// Drawn by `infoModalHost()` at the app's top (a full-screen cover hid the page it should frost over).
    func infoModal<Content: View>(isPresented: Binding<Bool>, title: String, symbol: String,
                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(InfoModalPresenter(isPresented: isPresented, title: title, symbol: symbol, body: content))
    }

    /// Where info cards are drawn: over everything this view holds (PrayerTimesView's root).
    func infoModalHost() -> some View { modifier(InfoModalHost()) }
}

/// The card showing now, if any (one at a time).
@MainActor @Observable final class InfoModalCenter {
    static let shared = InfoModalCenter()
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let content: AnyView
        let close: () -> Void
    }
    var item: Item?
}

private struct InfoModalPresenter<Body: View>: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let symbol: String
    let body: () -> Body
    @State private var shownID: UUID?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, on in
                let center = InfoModalCenter.shared
                if on {
                    let item = InfoModalCenter.Item(title: title, symbol: symbol, content: AnyView(body()),
                                                    close: { isPresented = false })
                    shownID = item.id
                    center.item = item
                } else if center.item?.id == shownID {
                    center.item = nil
                }
            }
    }
}

private struct InfoModalHost: ViewModifier {
    @State private var center = InfoModalCenter.shared
    func body(content: Content) -> some View {
        content.overlay {
            if let item = center.item {
                InfoModal(title: item.title, symbol: item.symbol, close: {
                    item.close()
                    if center.item?.id == item.id { center.item = nil }
                }) { item.content }
                .id(item.id)
            }
        }
    }
}

/// The card: the section's symbol and name, ✕ in the corner, then its explanation.
struct InfoModal<Content: View>: View {
    let title: String
    let symbol: String
    let close: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    /// The explanation's own height: the card is as tall as it needs, up to 60 % of the screen, then it scrolls inside
    /// (owner: small phones).
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ZStack {
            // A very light frost: the page stays in view behind it, softened (owner: "a very transparent material").
            Rectangle().fill(.ultraThinMaterial)
                .opacity(shown ? 0.75 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Color.sage)
                        .frame(width: 28)
                    Text(title)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                    Spacer(minLength: 8)
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                GeometryReader { geo in
                    ScrollView {
                        content()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.automatic)
                    .frame(height: geo.size.height)
                }
                .frame(height: min(max(contentHeight, 1), UIScreen.main.bounds.height * 0.6))
            }
            .padding(22)
            .frame(maxWidth: 440, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 26, y: 10)
            .padding(.horizontal, 22)
            .scaleEffect(shown || reduceMotion ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
        }
        .fontDesign(.rounded)
        .onAppear { withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) { shown = true } }
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.2)) { shown = false } completion: { close() }
    }
}

/// One line of an explanation: a symbol, a short name, what it means.
struct InfoModalRow: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
                Text(text).font(.system(.subheadline, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
