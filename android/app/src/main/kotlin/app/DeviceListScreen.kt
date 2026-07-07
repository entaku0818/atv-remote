package app

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

/** Mirrors DeviceListView.swift: a list of Android TVs found via mDNS. */
@Composable
fun DeviceListScreen(onSelectDevice: (DeviceDiscovery.Device) -> Unit) {
    val context = LocalContext.current
    val discovery = remember { DeviceDiscovery(context) }
    var devices by remember { mutableStateOf<List<DeviceDiscovery.Device>>(emptyList()) }

    DisposableEffect(discovery) {
        discovery.start { found -> devices = found }
        onDispose { discovery.stop() }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("デバイス") }) },
    ) { padding ->
        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            if (devices.isEmpty()) {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(16.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                        Text("Android TVを検索中…", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            items(devices, key = { it.name }) { device ->
                ListItem(
                    headlineContent = { Text(device.name) },
                    supportingContent = { Text(device.host ?: "解決中…") },
                    modifier = Modifier
                        .fillMaxWidth()
                        .then(if (device.host != null) Modifier.clickable { onSelectDevice(device) } else Modifier),
                )
                HorizontalDivider()
            }
        }
    }
}
