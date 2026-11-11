import Foundation
import HerdrKit
import IslandCore

/// Turns a delivery plan into a frozen payload. Attachments are validated
/// before the screenshot is taken, so a missing file stops the send instead of
/// producing a prompt that points at nothing. A denied or failed screenshot
/// only degrades the payload to text and files.
enum DeliveryService {
    static let permissionNotice = "屏幕录制未授权，本次只发送文字和文件。"
    static let captureNotice = "窗口截图失败，本次只发送文字和文件。"

    static func prepare(_ plan: DeliveryPlan) async -> Result<DeliveryPayload, BackendFailure> {
        if let failure = missingAttachment(in: plan.attachments) {
            return .failure(failure)
        }

        var screenshotPath: String?
        var screenshotFailure: String?
        var context = plan.context
        if let target = plan.target {
            // The context is read again at send time. The stored value survives
            // a read that comes back empty, because focusing the island can
            // clear AX's selection mid-compose.
            context = ContextLimits.merged(
                stored: plan.context,
                fresh: await WindowContextService.read(target)
            )
            if WindowCaptureService.isAuthorized {
                switch await WindowCaptureService.capture(target) {
                case .success(let path):
                    screenshotPath = path
                case .failure(let failure):
                    screenshotFailure = failure.kind == .screenCapturePermission
                        ? permissionNotice
                        : captureNotice
                }
            } else {
                screenshotFailure = permissionNotice
            }
        }

        return .success(DeliveryPayload(
            token: plan.token,
            task: plan.task,
            target: plan.target,
            screenshotPath: screenshotPath,
            screenshotFailure: screenshotFailure,
            context: context,
            attachments: plan.attachments,
            capturedAt: plan.capturedAt
        ))
    }

    /// A queued payload was prepared earlier. Files or the screenshot may have
    /// disappeared since then, so re-check rather than sending dead paths.
    static func dispatchable(_ payload: DeliveryPayload) -> DeliveryPayload {
        let attachments = payload.attachments.filter { isReadableFile($0.path) }
        let screenshot = payload.screenshotPath.flatMap { isReadableFile($0) ? $0 : nil }
        guard attachments != payload.attachments || screenshot != payload.screenshotPath else {
            return payload
        }
        return DeliveryPayload(
            token: payload.token,
            task: payload.task,
            target: payload.target,
            screenshotPath: screenshot,
            screenshotFailure: screenshot == nil && payload.screenshotPath != nil
                ? captureNotice
                : payload.screenshotFailure,
            context: payload.context,
            attachments: attachments,
            capturedAt: payload.capturedAt
        )
    }

    static func prompt(_ payload: DeliveryPayload, label: String = "Main agent drop") -> String {
        WindowPrompt.text(
            target: payload.target,
            screenshotPath: payload.screenshotPath,
            context: payload.context,
            attachments: payload.attachments,
            task: payload.task,
            capturedAt: payload.capturedAt,
            label: label
        )
    }

    static func missingAttachment(in attachments: [DeliveryAttachment]) -> BackendFailure? {
        for attachment in attachments where !isReadableFile(attachment.path) {
            return BackendFailure(.attachmentMissing, "找不到文件：\(attachment.path)")
        }
        return nil
    }

    private static func isReadableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return false
        }
        return !isDirectory.boolValue
    }
}
