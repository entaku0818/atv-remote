package atvremotekit

sealed class ATVError(message: String) : Exception(message) {
    class CertificateCreation(message: String) : ATVError("Certificate creation failed: $message")
    class ConnectionClosed(message: String) : ATVError("Connection closed: $message")
    class PairingFailed(message: String) : ATVError("Pairing failed: $message")
    class InvalidPairingCode(message: String) : ATVError("Invalid pairing code: $message")
}
