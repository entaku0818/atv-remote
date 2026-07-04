import ATVRemoteKit
import Foundation

// atvremote-cli — E2E harness for ATVRemoteKit against a real Android TV.
//
//   atvremote-cli discover           list Android TVs on the LAN
//   atvremote-cli <ip>               connect (pairing if needed) + interactive REPL
//
// REPL commands: key <KEYCODE> / home / power / app <url> / tver <url|id> / info / quit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fail("usage: atvremote-cli <discover|TV_IP>")
}

setbuf(stdout, nil)

if args[1] == "discover" {
    let discovery = DeviceDiscovery()
    print("Browsing for _androidtvremote2._tcp (10s)...")
    discovery.start { devices in
        for device in devices {
            print("  [found] \(device.name)  ip=\(device.host ?? "resolving...")  port=\(device.port.map(String.init) ?? "-")")
        }
    }
    Thread.sleep(forTimeInterval: 10)
    exit(0)
}

let host = args[1]

@MainActor
func run() async {
    let identity: ClientIdentity
    do {
        identity = try ClientIdentity.loadOrCreate()
    } catch {
        fail("client identity: \(error.localizedDescription)")
    }

    var remote = RemoteSession(host: host, identity: identity)
    do {
        try await remote.connect()
    } catch {
        print("Not paired yet (\(error.localizedDescription)); starting pairing.")
        do {
            let pairing = PairingSession(host: host, clientName: "atv-remote-poc", identity: identity)
            try await pairing.start()
            print("A 6-digit code should appear on the TV screen.")
            print("Enter the 6-digit code shown on the TV: ", terminator: "")
            guard let code = readLine(strippingNewline: true), !code.isEmpty else {
                fail("no pairing code entered")
            }
            try await pairing.finish(code: code)
            print("Pairing succeeded.")
        } catch {
            fail("pairing: \(error.localizedDescription)")
        }
        remote = RemoteSession(host: host, identity: identity)
        do {
            try await remote.connect()
        } catch {
            fail("reconnect after pairing: \(error.localizedDescription)")
        }
    }

    let info = remote.deviceInfo
    print("Connected to \(info?.model ?? "?") (\(info?.vendor ?? "?"), sw \(info?.version ?? "?")) at \(host)")
    print("Type 'quit' to exit.")

    while true {
        print("atv> ", terminator: "")
        guard let line = readLine(strippingNewline: true) else { break }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let argument = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""

        switch command {
        case "quit":
            remote.disconnect()
            exit(0)
        case "key" where !argument.isEmpty:
            do {
                try remote.sendKey(named: argument)
                print("sent \(argument.uppercased())")
            } catch {
                print("unknown key: \(argument)")
            }
        case "home":
            remote.sendKey(.keycodeHome)
            print("sent HOME")
        case "power":
            remote.sendKey(.keycodePower)
            print("sent POWER")
        case "app" where !argument.isEmpty:
            remote.launchApp(argument)
            print("launched \(argument)")
        case "tver" where !argument.isEmpty:
            let url = argument.hasPrefix("http") ? argument : "https://tver.jp/episodes/\(argument)"
            remote.launchApp(url)
            print("launched \(url)")
        case "info":
            let info = remote.deviceInfo
            print("device: \(info?.vendor ?? "?") \(info?.model ?? "?") sw \(info?.version ?? "?")")
            print("is_on: \(remote.isOn)")
            print("current_app: \(remote.currentApp)")
        default:
            print("commands: key <KEYCODE> / home / power / app <url> / tver <url|id> / info / quit")
        }
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task { @MainActor in
    await run()
    semaphore.signal()
}
semaphore.wait()
