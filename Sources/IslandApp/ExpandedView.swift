import IslandCore
import SwiftUI

struct ExpandedView: View {
    let presentation: IslandPresentation
    let actions: IslandViewActions
    var notchWidth: CGFloat?
    var notchHeight: CGFloat = 0

    var body: some View {
        switch presentation.surface {
        case .detail:
            DetailView(
                presentation: presentation,
                actions: actions,
                notchWidth: notchWidth,
                notchHeight: notchHeight
            )
        case .deck:
            if presentation.quickTask != nil || presentation.windowTask != nil {
                taskSurface
            } else {
                DeckView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth,
                    notchHeight: notchHeight
                )
            }
        case .peek:
            PeekView(
                presentation: presentation,
                actions: actions,
                notchWidth: notchWidth,
                notchHeight: notchHeight
            )
        case .ambient, .drop:
            Color.clear
        }
    }

    private var taskSurface: some View {
        VStack(spacing: 0) {
            if let notchWidth, notchHeight > 0 {
                AmbientBarView(
                    presentation: presentation,
                    actions: actions,
                    notchWidth: notchWidth
                )
                .frame(height: notchHeight)
            }
            Group {
                if let quickTask = presentation.quickTask {
                    QuickTaskView(quickTask: quickTask, actions: actions)
                } else if let windowTask = presentation.windowTask {
                    WindowTaskView(
                        presentation: presentation,
                        windowTask: windowTask,
                        actions: actions
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
    }

    private var background: some View {
        Group {
            if let notchWidth, notchHeight > 0 {
                NotchIslandShape(
                    neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                    neckHeight: notchHeight
                )
                .fill(LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: Theme.bar, location: 0.10),
                        .init(color: Theme.surface, location: 0.34),
                        .init(color: Theme.surface, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(alignment: .top) {
                    NotchCollarFill(
                        neckWidth: notchWidth + IslandGeometry.notchEarWidth * 2,
                        neckHeight: notchHeight
                    )
                }
            } else {
                RoundedRectangle(cornerRadius: 20).fill(Theme.surface)
            }
        }
    }
}
