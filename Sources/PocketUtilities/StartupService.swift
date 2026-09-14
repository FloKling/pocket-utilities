import AppKit
import Combine
import ServiceManagement

final class LoginItemService: ObservableObject {
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var error: String?
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    init(readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
         register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
         unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }) {
        self.readStatus = readStatus; self.register = register; self.unregister = unregister
        status = readStatus()
    }
    var requested: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = readStatus() }
    func setEnabled(_ enabled: Bool) {
        error = nil
        do {
            if enabled { try register() } else { try unregister() }
        } catch { self.error = "Could not change Launch at Login: \(error.localizedDescription)" }
        refresh()
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct StartupState: Codable, Equatable {
    var restoreUtilities = true
    var keepAwake = false
    var awakeDeadline: Date?
    var mouseJiggler = false

    func restore(awake: KeepAwakeService, enableJiggler: (Bool) throws -> Void) -> [String] {
        guard restoreUtilities else { return [] }
        var errors: [String] = []
        if keepAwake {
            do { try awake.enable(until: awakeDeadline) }
            catch { errors.append("Keep Awake: \(error.localizedDescription)") }
        }
        if mouseJiggler {
            do { try enableJiggler(true) }
            catch { errors.append("Mouse Jiggler: \(error.localizedDescription)") }
        }
        return errors
    }
}
