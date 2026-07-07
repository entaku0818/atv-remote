package app

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import java.io.File
import remote.Remotemessage.RemoteKeyCode

/** Mirrors RemoteView.swift: connection status, D-pad, system keys, app-link launcher. */
@Composable
fun RemoteScreen(device: DeviceDiscovery.Device, identityDir: File, onBack: () -> Unit) {
    val viewModel = remember(device.host) { RemoteViewModel(device.host ?: "", identityDir) }
    var appLinkUrl by remember { mutableStateOf("https://tver.jp/episodes/") }

    BackHandler(onBack = onBack)
    DisposableEffect(viewModel) { onDispose { viewModel.close() } }
    LaunchedEffect(viewModel) { viewModel.connect() }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(device.name) },
                navigationIcon = { TextButton(onClick = onBack) { Text("戻る") } },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            StatusSection(viewModel)
            if (viewModel.phase == RemotePhase.Connected) {
                DpadSection(viewModel)
                SystemKeysSection(viewModel)
                AppLinkSection(appLinkUrl, onUrlChange = { appLinkUrl = it }, onLaunch = { viewModel.launchAppLink(appLinkUrl) })
            }
        }
    }
}

@Composable
private fun StatusSection(viewModel: RemoteViewModel) {
    when (val phase = viewModel.phase) {
        RemotePhase.Idle, RemotePhase.Connecting -> {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator()
                Text("接続中…")
            }
        }
        RemotePhase.PairingCodeRequired, RemotePhase.Pairing -> {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("TVに表示された6桁コードを入力してください")
                OutlinedTextField(
                    value = viewModel.pairingCode,
                    onValueChange = { if (it.length <= 6) viewModel.pairingCode = it.uppercase() },
                    label = { Text("6桁コード") },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Text,
                        capitalization = KeyboardCapitalization.Characters,
                    ),
                )
                Button(
                    onClick = { viewModel.submitPairingCode() },
                    enabled = viewModel.pairingCode.length == 6 && phase != RemotePhase.Pairing,
                ) {
                    Text("ペアリング")
                }
            }
        }
        RemotePhase.Connected -> {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("接続済み", color = MaterialTheme.colorScheme.primary)
                Text(viewModel.deviceDescription, style = MaterialTheme.typography.bodySmall)
                if (viewModel.currentApp.isNotEmpty()) {
                    Text(viewModel.currentApp, style = MaterialTheme.typography.labelSmall)
                }
            }
        }
        is RemotePhase.Failed -> {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(phase.message, color = MaterialTheme.colorScheme.error)
                Button(onClick = { viewModel.connect() }) { Text("再接続") }
            }
        }
    }
}

@Composable
private fun DpadSection(viewModel: RemoteViewModel) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        KeyButton("▲", RemoteKeyCode.KEYCODE_DPAD_UP, viewModel)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KeyButton("◀", RemoteKeyCode.KEYCODE_DPAD_LEFT, viewModel)
            Button(onClick = { viewModel.send(RemoteKeyCode.KEYCODE_DPAD_CENTER) }, modifier = Modifier.size(64.dp)) {
                Text("OK")
            }
            KeyButton("▶", RemoteKeyCode.KEYCODE_DPAD_RIGHT, viewModel)
        }
        KeyButton("▼", RemoteKeyCode.KEYCODE_DPAD_DOWN, viewModel)
    }
}

@Composable
private fun KeyButton(label: String, key: RemoteKeyCode, viewModel: RemoteViewModel) {
    OutlinedButton(onClick = { viewModel.send(key) }, modifier = Modifier.size(64.dp)) {
        Text(label)
    }
}

@Composable
private fun SystemKeysSection(viewModel: RemoteViewModel) {
    Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        OutlinedButton(onClick = { viewModel.send(RemoteKeyCode.KEYCODE_BACK) }) { Text("戻る") }
        OutlinedButton(onClick = { viewModel.send(RemoteKeyCode.KEYCODE_HOME) }) { Text("ホーム") }
        OutlinedButton(onClick = { viewModel.send(RemoteKeyCode.KEYCODE_POWER) }) { Text("電源") }
    }
}

@Composable
private fun AppLinkSection(url: String, onUrlChange: (String) -> Unit, onLaunch: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            "TVer・Netflix・YouTube・Prime Video・Disney+・AbemaTVなどのURLを開けます",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = url,
            onValueChange = onUrlChange,
            label = { Text("アプリのURL（例: https://tver.jp/episodes/...）") },
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, capitalization = KeyboardCapitalization.None),
            modifier = Modifier.fillMaxWidth(),
        )
        Button(onClick = onLaunch, enabled = url.startsWith("http"), modifier = Modifier.fillMaxWidth()) {
            Text("TVで開く")
        }
    }
}
