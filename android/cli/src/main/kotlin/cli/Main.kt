package cli

import atvremotekit.ATVError
import atvremotekit.ClientIdentity
import atvremotekit.PairingSession
import atvremotekit.RemoteSession
import java.io.File
import kotlinx.coroutines.runBlocking
import remote.Remotemessage.RemoteKeyCode

/**
 * atvremote-cli (Kotlin/JVM) — E2E harness for the atvremotekit library
 * against a real Android TV, mirroring ATVRemoteKit's atvremote-cli.
 *
 *   ./gradlew :cli:run --args="<TV_IP>"   connect (pairing if needed) + interactive REPL
 *
 * REPL commands: key <KEYCODE> / home / power / app <url> / tver <url|id> / info / quit
 */
fun main(args: Array<String>) {
    if (args.size != 1) {
        System.err.println("usage: atvremote-cli <TV_IP>")
        kotlin.system.exitProcess(1)
    }
    val host = args[0]

    val certDir = File("certs/android")
    val identity = ClientIdentity.loadOrCreate(File(certDir, "key.der"), File(certDir, "cert.der"))

    runBlocking {
        var remote = RemoteSession(host, identity = identity)
        try {
            remote.connect()
        } catch (e: Exception) {
            println("Not paired yet (${e.message}); starting pairing.")
            val pairing = PairingSession(host, clientName = "atv-remote-poc", identity = identity)
            try {
                pairing.start()
                println("A 6-digit code should appear on the TV screen.")
                print("Enter the 6-digit code shown on the TV: ")
                val code = readlnOrNull()?.trim()
                if (code.isNullOrEmpty()) {
                    System.err.println("error: no pairing code entered")
                    kotlin.system.exitProcess(1)
                }
                pairing.finish(code)
                println("Pairing succeeded.")
            } catch (pairingError: Exception) {
                System.err.println("error: pairing: ${pairingError.message}")
                kotlin.system.exitProcess(1)
            }
            remote = RemoteSession(host, identity = identity)
            try {
                remote.connect()
            } catch (reconnectError: Exception) {
                System.err.println("error: reconnect after pairing: ${reconnectError.message}")
                kotlin.system.exitProcess(1)
            }
        }

        val info = remote.deviceInfo
        println("Connected to ${info?.model ?: "?"} (${info?.vendor ?: "?"}, sw ${info?.version ?: "?"}) at $host")
        println("Type 'quit' to exit.")

        while (true) {
            print("atv> ")
            val line = readlnOrNull() ?: break
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            val parts = trimmed.split(" ", limit = 2)
            val command = parts[0].lowercase()
            val argument = if (parts.size > 1) parts[1].trim() else ""

            when {
                command == "quit" -> {
                    remote.disconnect()
                    return@runBlocking
                }
                command == "key" && argument.isNotEmpty() -> {
                    try {
                        remote.sendKey(argument)
                        println("sent ${argument.uppercase()}")
                    } catch (e: ATVError) {
                        println("unknown key: $argument")
                    }
                }
                command == "home" -> {
                    remote.sendKey(RemoteKeyCode.KEYCODE_HOME)
                    println("sent HOME")
                }
                command == "power" -> {
                    remote.sendKey(RemoteKeyCode.KEYCODE_POWER)
                    println("sent POWER")
                }
                command == "app" && argument.isNotEmpty() -> {
                    remote.launchApp(argument)
                    println("launched $argument")
                }
                command == "tver" && argument.isNotEmpty() -> {
                    val url = if (argument.startsWith("http")) argument else "https://tver.jp/episodes/$argument"
                    remote.launchApp(url)
                    println("launched $url")
                }
                command == "info" -> {
                    val current = remote.deviceInfo
                    println("device: ${current?.vendor ?: "?"} ${current?.model ?: "?"} sw ${current?.version ?: "?"}")
                    println("is_on: ${remote.isOn}")
                    println("current_app: ${remote.currentApp}")
                }
                else -> println("commands: key <KEYCODE> / home / power / app <url> / tver <url|id> / info / quit")
            }
        }
    }
}
