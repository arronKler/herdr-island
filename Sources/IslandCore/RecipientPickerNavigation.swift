/// The keyboard highlight in the recipient picker. It is transient UI state,
/// so it lives here as pure functions rather than in the reducer.
public enum RecipientPickerNavigation {
    /// The row the picker opens on: the current recipient when it is in the
    /// list, otherwise the first row.
    public static func initial(
        recipients: [DeliveryRecipientOption],
        current: PaneID?
    ) -> PaneID? {
        guard let current, recipients.contains(where: { $0.pane == current }) else {
            return recipients.first?.pane
        }
        return current
    }

    /// Moves the highlight by delta, clamped at both ends so the ends are
    /// stable and a long list cannot be cycled past by accident.
    public static func move(
        _ highlighted: PaneID?,
        by delta: Int,
        in recipients: [DeliveryRecipientOption]
    ) -> PaneID? {
        guard !recipients.isEmpty else { return nil }
        guard let highlighted,
              let index = recipients.firstIndex(where: { $0.pane == highlighted }) else {
            return delta < 0 ? recipients.last?.pane : recipients.first?.pane
        }
        let target = min(max(index + delta, 0), recipients.count - 1)
        return recipients[target].pane
    }
}
