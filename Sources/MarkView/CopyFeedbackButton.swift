import SwiftUI

// A toolbar button that flashes a checkmark + "Copied" for a short moment
// after a successful copy action. Each instance tracks its own feedback
// state, so multiple copy buttons never interfere with each other.
// Rapid re-clicks restart the timer (the confirmation stays visible).
struct CopyFeedbackButton: View {
    let title: String
    let systemImage: String
    /// Performs the copy; returns true when something was copied.
    let action: () -> Bool

    private static let feedbackDuration: Duration = .seconds(1.5)

    @State private var showingConfirmation = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            guard action() else { return }
            withAnimation(.easeIn(duration: 0.1)) {
                showingConfirmation = true
            }
            // Restart the timer on every click so quick repeats behave sanely.
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: Self.feedbackDuration)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    showingConfirmation = false
                }
            }
        } label: {
            Label(
                showingConfirmation ? "Copied" : title,
                systemImage: showingConfirmation ? "checkmark" : systemImage
            )
            .foregroundStyle(showingConfirmation ? Color.green : Color.primary)
        }
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
    }
}
