import MailKit

class MailExtension: NSObject, MEExtension {
    func handlerForMessageSecurity() -> MEMessageSecurityHandler {
        // Shared instance: the handler keeps no per-message state.
        return MessageSecurityHandler.shared
    }
}
