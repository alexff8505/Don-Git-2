import Foundation

extension Notification.Name {
    static let focusRepositories = Notification.Name("focusRepositories")
    static let focusCommitHistory = Notification.Name("focusCommitHistory")
    static let focusChangedFiles = Notification.Name("focusChangedFiles")
    static let focusCodeDiff = Notification.Name("focusCodeDiff")
    static let navigateChangedFile = Notification.Name("navigateChangedFile")
    static let navigateDiffChange = Notification.Name("navigateDiffChange")
    static let refreshHistoryRequested = Notification.Name("refreshHistoryRequested")
    static let addRepositoryRequested = Notification.Name("addRepositoryRequested")
}
