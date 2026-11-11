import IslandCore
import SwiftUI

/// The lock host. The shared composer card is centered inside the 380-wide
/// panel; the locked window stays on the desktop and the header pill says it
/// is still locked.
struct WindowTaskView: View {
    let composer: DeliveryComposerPresentation
    let actions: IslandViewActions

    var body: some View {
        VStack(spacing: 0) {
            DeliveryComposerCard(
                composer: composer,
                actions: actions
            )
            .frame(width: 340)
            .padding(.top, IslandGeometry.expandedTopInset)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
