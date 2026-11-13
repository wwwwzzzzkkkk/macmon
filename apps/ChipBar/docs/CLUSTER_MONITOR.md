# ChipBar Cluster Monitor v3.6

ChipBar 3.6 introduces **opt-in, read-only LAN monitoring**. It does **not**
start, stop, cancel, schedule, execute, or otherwise control simulations.
Users and external tools such as GPT/Codex retain full control of computations.

## 配对两台 Mac（无需复制密钥）

1. 在两台 Mac 上安装同一版 ChipBar，并打开菜单栏里的 **计算集群** 页面。
2. 搜索启动后，在「附近设备」中选择另一台 Mac，点击 **配对**。
3. 两边屏幕显示六位数字。确认两组数字**完全相同**后，
   分别点击 **数字一致，确认配对**。
4. ChipBar 会记住授权设备，并自动开启只读监控。之后只需运行
   ChipBar，无需再次复制密钥或重复配对。

每台 Mac 只在配对前传输设备名称和 X25519 公钥；监控数据
直到双方都在本机确认了同一个六位配对码、保存对方公钥后才交换。
32 字节会话密钥通过 X25519 + HKDF 分别生成，不经明文网络发送；
每帧监控数据继续使用 AES-256-GCM 加密及认证。
私钥、已信任的公钥存在各自 macOS 钥匙串中。不要在不可信设备或
无法核对配对数字的情况下确认配对。

可随时通过「共享」开关暂停本机共享；只读监控不包含任何
远程 Shell、任务调度或仿真启动/停止功能。

## 雷雳桥接连接检查

单独插上雷雳线不保证已建立可发现的 IP 网络。
在**两台** Mac 的「系统设置 → 网络」确认 **Thunderbolt Bridge**
已存在且处于已连接状态，TCP/IP 有可用地址；没有该服务就先新增。
此外，在「系统设置 → 隐私与安全性 → 本地网络」允许 ChipBar，
并在两台 Mac 的集群页保持搜索状态。
ChipBar 通过 Bonjour 搜索本地网络，可经可达的雷雳桥接或 Wi-Fi
进行通信；目前不会将任意检测到的雷雳设备误认为计算节点。
若打开了网络隔离、防火墙阻断或 MacBook 睡眠，设备可能不可达。

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
- Pairing requires both users to visually compare and confirm a six-digit
  X25519 short authentication string. No monitoring values are sent before
  mutual approval. Bonjour still exposes service availability and the hello
  includes a device name and public key. No certificate-backed node identity
  or centralized PKI is implemented.
- Use trusted local networks only. This is not a public-internet service.
- The first version sends small snapshots every three seconds, only to
  separately trusted nodes. It does not
  transfer files, expose logs, or offer GPU cluster scheduling.
- LAN availability is subject to Bonjour routing, local-network permissions,
  macOS sleep, firewall and network isolation. CI compilation cannot prove
  cross-device connectivity without testing two physical Macs.
- None of the existing macmon hardware samplers, power accounting, or
  WidgetKit kinds were changed.
