import MailKit

/// Message "decoder" that does no cryptography at all: it only rewrites
/// RFC 2231 attachment filename parameters that Mail.app fails to display
/// into the RFC 2047 form Mail renders correctly. Returns nil (untouched)
/// for every message that doesn't need the fix.
class MessageSecurityHandler: NSObject, MEMessageSecurityHandler {

    static let shared = MessageSecurityHandler()

    // MARK: - Encoding (outgoing) — not used, pass through

    func getEncodingStatus(for message: MEMessage,
                           composeContext: MEComposeContext,
                           completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        completionHandler(MEOutgoingMessageEncodingStatus(
            canSign: false, canEncrypt: false,
            securityError: nil, addressesFailingEncryption: []))
    }

    func encode(_ message: MEMessage,
                composeContext: MEComposeContext,
                completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        completionHandler(MEMessageEncodingResult(
            encodedMessage: nil, signingError: nil, encryptionError: nil))
    }

    // MARK: - Decoding (incoming)

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        guard let fixed = FilenameFixer.fix(data) else { return nil }
        let info = MEMessageSecurityInformation(
            signers: [], isEncrypted: false, signingError: nil, encryptionError: nil)
        return MEDecodedMessage(data: fixed, securityInformation: info, context: nil)
    }

    // MARK: - UI hooks — nothing to show

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        return nil
    }

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        return nil
    }

    func primaryActionClicked(forMessageContext context: Data,
                              completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        completionHandler(nil)
    }
}
