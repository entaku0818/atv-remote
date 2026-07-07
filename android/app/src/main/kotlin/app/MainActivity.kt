package app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import java.io.File

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val identityDir = File(filesDir, "atv-remote")
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier, color = MaterialTheme.colorScheme.background) {
                    App(identityDir)
                }
            }
        }
    }
}

@Composable
private fun App(identityDir: File) {
    var selectedDevice by remember { mutableStateOf<DeviceDiscovery.Device?>(null) }

    val device = selectedDevice
    if (device == null) {
        DeviceListScreen(onSelectDevice = { selectedDevice = it })
    } else {
        RemoteScreen(device = device, identityDir = identityDir, onBack = { selectedDevice = null })
    }
}
