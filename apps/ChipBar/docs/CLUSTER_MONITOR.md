# ChipBar Cluster Monitor v3.6

ChipBar 3.6 introduces **opt-in, read-only LAN monitoring**. It does **not**
start, stop, cancel, schedule, execute, or otherwise control simulations.
Users and external tools such as GPT/Codex retain full control of computations.

## Pair two Macs

1. Install the same v3.6 build on both Macs and leave ChipBar running.
2. Open the new **计算集群** home tile on the first Mac.
3. Select **生成共享密钥** and **复制共享密钥**. Transfer this secret
   over a trusted channel; do not publish it or paste it in chats.
4. Open the tile on the second Mac and use **从剪贴板导入**.
5. Enable **允许局域网共享只读监控数据** on **both** Macs.
6. Keep both devices on the same Bonjour-accessible LAN, and grant macOS
   local-network permission if prompted. No public port or remote shell is used.

The 256-bit random key is stored in each user's macOS Keychain, not UserDefaults.
Bonjour advertises service availability; telemetry frames are AES-256-GCM
authenticated and encrypted at the application layer (this prototype does
not use TLS certificates). A new imported key takes effect immediately and
clears old peer snapshots; other Macs must import the same key to reconnect.
Disable sharing on either device to stop its service.

## External simulation state (optional)

ChipBar reads, but never writes, the following file on each Mac:

`~/Library/Application Support/ChipBar/cluster-status.json`

An external orchestration script can publish a single **small** JSON object,
preferably by writing a temporary file and atomically renaming it:

```json
{
  "tasks": [
    {"id": "case-001", "title": "OpenFAST case 001",
     "state": "running", "progress": 0.42},
    {"id": "case-002", "title": "OpenFAST case 002",
     "state": "running", "progress": null}
  ]
}
```

- `progress` is a fraction in **0...1**, not an estimated CPU percentage.
- If external progress is unavailable, omit the field or set it to `null`;
  ChipBar displays **进度未知**.
- Maximum file size is 64 KiB and up to 12 task entries are displayed.
- As of v3.6, ChipBar does **not** infer simulation progress from process
  names, CPU load, logs or guessed output file sizes. External tools own the
  lifecycle and validity of this file.
- A stale external file is not automatically interpreted as proof that a
  simulation is still running. External scripts should remove or update their
  own task entries when tasks end; do not rely on the file as an authoritative
  process inventory.

## Limitations of the first version

- ChipBar itself must remain running on both Macs. A separate login-item
  LaunchAgent is **not** included in this release.
- The shared-key pairing flow is manual. No unauthenticated metrics are
  transmitted, but Bonjour exposes the service name and peers on the same
  subnet may attempt connections. Application-layer authentication uses the
  shared secret; no certificate-backed node identity is implemented.
- Use trusted local networks only. This is not a public-internet service.
- The first version sends small snapshots every three seconds. It does not
  transfer files, expose logs, or offer GPU cluster scheduling.
- LAN availability is subject to Bonjour routing, local-network permissions,
  macOS sleep, firewall and network isolation. CI compilation cannot prove
  cross-device connectivity without testing two physical Macs.
- None of the existing macmon hardware samplers, power accounting, or
  WidgetKit kinds were changed.
