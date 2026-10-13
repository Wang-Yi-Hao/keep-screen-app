import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 常亮小助手 —— V2（仅安卓）
/// 科技风 UI：深色背景 + 霓虹青发光质感。
/// V2 新增：定时关闭 / 充电时常亮 / 指定 App 前台时常亮。
/// 通过 MethodChannel 调原生，EventChannel 接收实时状态。

const String _channelName = 'com.keepscreen.app/keep';
const String _eventName = 'com.keepscreen.app/events';

/// 远程版本信息数据源列表：依次尝试，任一成功即用。
/// 1. 自建轻量服务器（Lighthouse，广州）：最稳，国内直连、无 CDN 缓存；
/// 2. GitHub Contents API：返回仓库文件的实时内容（不经过 CDN 缓存），
///    响应为 base64，需单独解码（见 _fetchJson）；
/// 3/4. jsDelivr CDN 镜像（国内可达，但有最长约 12 小时缓存）；
/// 5. GitHub raw 原始地址（兜底）。
/// 发布新版本时，把服务器上的 version.json 的 versionCode 改大即可触发更新提示
/// （同时记得把服务器上的 APK 与仓库 version.json 一并更新）。
const List<String> _updateInfoUrls = [
  'http://106.53.120.233/version.json',
  'https://api.github.com/repos/Wang-Yi-Hao/keep-screen-app/contents/version.json',
  'https://cdn.jsdelivr.net/gh/Wang-Yi-Hao/keep-screen-app@main/version.json',
  'https://fastly.jsdelivr.net/gh/Wang-Yi-Hao/keep-screen-app@main/version.json',
  'https://raw.githubusercontent.com/Wang-Yi-Hao/keep-screen-app/main/version.json',
];

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 开启全面屏/edge-to-edge，避免右侧/底部系统黑框（V1 已修）
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const KeepScreenApp());
}

class KeepScreenApp extends StatefulWidget {
  const KeepScreenApp({super.key});

  @override
  State<KeepScreenApp> createState() => _KeepScreenAppState();
}

class _KeepScreenAppState extends State<KeepScreenApp> {
  bool _ready = false;
  bool _showGuide = false;

  @override
  void initState() {
    super.initState();
    _checkGuide();
  }

  Future<void> _checkGuide() async {
    bool guideDone = false;
    try {
      final state = await const MethodChannel(_channelName)
          .invokeMethod<Map<Object?, Object?>>('getState');
      if (state != null) guideDone = state['guideDone'] == true;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _showGuide = !guideDone; // 未完成引导 → 先走权限页
      _ready = true;
    });
  }

  void _enterApp() => setState(() => _showGuide = false);

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF070B1E),
        ),
        home: const Scaffold(backgroundColor: Color(0xFF070B1E)),
      );
    }
    return MaterialApp(
      title: '常亮小助手',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFF7A5CFF),
        ),
      ),
      home: _showGuide
          ? PermissionPage(onEnter: _enterApp)
          : const HomePage(),
    );
  }
}

/// 首次启动权限引导页：以“推荐/可选”方式展示权限，均可跳过，不授予也能进入应用。
/// 也可从“设置”里再次打开。onEnter 为 null 时（从设置进入）以 pop 返回。
class PermissionPage extends StatefulWidget {
  final VoidCallback? onEnter;
  const PermissionPage({super.key, this.onEnter});

  @override
  State<PermissionPage> createState() => _PermissionPageState();
}

class _PermissionPageState extends State<PermissionPage>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(_channelName);

  bool _batteryOpt = false;
  bool _overlay = false;
  bool _usage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final batt =
        await _channel.invokeMethod<bool>('checkBatteryOptimization') ?? false;
    final ov =
        await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
    final us =
        await _channel.invokeMethod<bool>('checkUsagePermission') ?? false;
    if (!mounted) return;
    setState(() {
      _batteryOpt = batt;
      _overlay = ov;
      _usage = us;
    });
  }

  Future<void> _enter() async {
    await _channel.invokeMethod<void>('markGuideDone');
    if (widget.onEnter != null) {
      widget.onEnter!();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _openBattery() async =>
      _channel.invokeMethod<void>('requestBatteryOptimization');
  Future<void> _openOverlay() async =>
      _channel.invokeMethod<void>('openOverlaySettings');
  Future<void> _openUsage() async =>
      _channel.invokeMethod<void>('openUsageSettings');

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required bool required_,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00F0FF), size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          granted
              ? const Chip(
                  label: Text('已授予',
                      style: TextStyle(color: Colors.black, fontSize: 12)),
                  backgroundColor: Color(0xFF00F0FF),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              : ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B2138),
                    foregroundColor: const Color(0xFF00F0FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(required_ ? '去开启' : '可选'),
                ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B1E),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.2,
            colors: [Color(0xFF141A3A), Color(0xFF070B1E)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('欢迎使用',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 6),
                const Text('以下权限可提升常亮稳定性与扩展功能，均可跳过；不授予也能正常使用基础常亮，需要时可在设置中再开启',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 24),
                _row(
                  icon: Icons.battery_charging_full,
                  title: '电池优化白名单（推荐）',
                  subtitle: '加入后前台服务不易被系统回收，常亮更可靠',
                  granted: _batteryOpt,
                  required_: true,
                  onTap: _openBattery,
                ),
                _row(
                  icon: Icons.layers,
                  title: '悬浮窗权限（推荐）',
                  subtitle: '开启后 App 退到后台仍可保持常亮；不开启仅前台常亮',
                  granted: _overlay,
                  required_: true,
                  onTap: _openOverlay,
                ),
                _row(
                  icon: Icons.apps,
                  title: '使用情况访问（可选）',
                  subtitle: '“指定 App 前台时常亮”功能需要此权限',
                  granted: _usage,
                  required_: false,
                  onTap: _openUsage,
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _enter,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('进入应用',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel(_channelName);
  static const EventChannel _events = EventChannel(_eventName);

  // —— 实时状态（来自原生推送）——
  bool _isOn = false;
  bool _manualOn = false;
  bool _chargeMode = false;
  bool _charging = false;
  bool _foregroundMode = false;
  String _targetPackage = '';
  int _timerMinutes = 0; // 0 = 关闭定时
  int _remainingSeconds = -1;

  // —— 定时降低亮度（防烧屏）——
  bool _dimEnabled = false;
  int _dimMinutes = 5;
  bool _dimmed = false;

  // —— UI 侧状态 ——
  String _targetAppName = '';
  String? _targetAppIcon; // 已选应用图标（base64），用于卡片展示
  bool _usageGranted = true;
  bool _pendingForegroundEnable = false; // 等待用户从设置授权后补开

  // —— 检查更新 ——
  String _localVersion = '1.0.0';
  int _localVersionCode = 1;
  String _localAbi = ''; // 设备主 ABI（如 arm64-v8a），用于按架构下载 APK
  bool _checkingUpdate = false; // 手动检查更新进行中（显示加载动画）
  bool _downloading = false; // 应用内下载更新进行中
  bool _cancelDownload = false; // 用户取消下载
  double _downloadProgress = 0; // 下载进度 0~1；-1 表示未知总大小（不确定进度）
  bool _downloadDialogOpen = false; // 进度弹窗是否仍打开（防止重复 pop）

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events.receiveBroadcastStream().listen(_onState);
    _loadInitialState();
    _initVersion();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页返回（resume）时重新检查“使用情况访问”权限；
  /// 若此前因未授权而待开“指定 App”，则自动补开。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }

  Future<void> _onResumed() async {
    final granted =
        await _channel.invokeMethod<bool>('checkUsagePermission') ?? false;
    if (!mounted) return;
    setState(() => _usageGranted = granted);
    if (_pendingForegroundEnable) {
      _pendingForegroundEnable = false;
      if (granted) {
        setState(() => _foregroundMode = true);
        await _channel.invokeMethod<void>('setForegroundMode', {'enabled': true});
      }
    }
  }

  Future<void> _loadInitialState() async {
    try {
      final state = await _channel.invokeMethod<Map<Object?, Object?>>('getState');
      if (state != null) _applyState(state);
      // 使用情况访问权限（前台 App 检测需要）
      _usageGranted = await _channel.invokeMethod<bool>('checkUsagePermission') ?? true;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _onState(dynamic data) {
    if (data is Map) _applyState(data);
  }

  void _applyState(Map data) {
    setState(() {
      _isOn = _asBool(data['isOn']);
      _manualOn = _asBool(data['manualOn']);
      _chargeMode = _asBool(data['chargeMode']);
      _charging = _asBool(data['charging']);
      _foregroundMode = _asBool(data['foregroundMode']);
      _targetPackage = (data['targetPackage'] as String?) ?? '';
      _timerMinutes = _asInt(data['timerMinutes']);
      _remainingSeconds = _asInt(data['remainingSeconds']);
      _dimEnabled = _asBool(data['dimEnabled']);
      _dimMinutes = _clampDim(_asInt(data['dimMinutes']));
      _dimmed = _asBool(data['dimmed']);
      if (_targetPackage.isNotEmpty && _targetAppName.isEmpty) {
        // 名称在选应用时记录，这里仅保留包名
      }
    });
  }

  bool _asBool(dynamic v) => v == true;
  int _asInt(dynamic v) => (v is int) ? v : -1;
  int _clampDim(int v) => (v >= 1 && v <= 30) ? v : 5;

  // —— 命令封装 ——
  Future<void> _toggleManual() async {
    if (_manualOn) {
      await _channel.invokeMethod<void>('stop');
    } else {
      // 悬浮窗权限仅影响“后台常亮”；不授予也能在前台保持常亮，故不再强制。
      final bool hasPerm =
          await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      await _channel.invokeMethod<void>('start');
      if (!hasPerm && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('提示：未授予悬浮窗权限，App 退到后台将停止常亮'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      // 手动开启后，若已选定时，立即按当前分钟数计时
      if (_timerMinutes > 0) {
        await _channel.invokeMethod<void>(
            'setTimer', {'minutes': _timerMinutes});
      }
    }
  }

  Future<void> _setTimer(int minutes) async {
    setState(() => _timerMinutes = minutes);
    // 仅当手动开启时，定时器才真正生效
    if (_manualOn) {
      await _channel.invokeMethod<void>('setTimer', {'minutes': minutes});
    }
  }

  Future<void> _setChargeMode(bool on) async {
    setState(() => _chargeMode = on);
    await _channel.invokeMethod<void>('setChargeMode', {'enabled': on});
  }

  void _openPermissions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PermissionPage()),
    );
  }

  Future<void> _setForegroundMode(bool on) async {
    if (on) {
      _usageGranted =
          await _channel.invokeMethod<bool>('checkUsagePermission') ?? false;
      if (!_usageGranted) {
        // 未授权：记住意图并打开设置页，授权后由 didChangeAppLifecycleState 自动补开
        _pendingForegroundEnable = true;
        await _channel.invokeMethod<void>('openUsageSettings');
        return;
      }
    } else {
      _pendingForegroundEnable = false;
    }
    setState(() => _foregroundMode = on);
    await _channel.invokeMethod<void>('setForegroundMode', {'enabled': on});
  }

  Future<void> _pickApp() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const AppPickerPage()),
    );
    if (result != null) {
      setState(() {
        _targetPackage = result['package'] as String;
        _targetAppName = result['name'] as String;
        _targetAppIcon = result['icon'] as String?;
      });
      await _channel.invokeMethod<void>(
          'setTargetPackage', {'package': _targetPackage});
    }
  }

  // —— 定时降低亮度（防烧屏）——

  Future<void> _setDimMode(bool enabled, int minutes) async {
    // 分钟数始终本地更新（下拉选择）；开关仅在确认生效后才点亮
    setState(() => _dimMinutes = minutes);
    if (!enabled) {
      setState(() => _dimEnabled = false);
    }
    try {
      final res = await _channel.invokeMethod<String>(
          'setDimMode', {'enabled': enabled, 'minutes': minutes});
      if (res == 'need_permission' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请在系统设置中允许“修改系统设置”，以启用防烧屏降亮度'),
            duration: Duration(seconds: 4),
          ),
        );
      } else if (res == 'ok' && enabled && mounted) {
        setState(() => _dimEnabled = true);
      }
    } catch (_) {}
  }

  Future<void> _setDimEnabled(bool on) => _setDimMode(on, _dimMinutes);
  Future<void> _setDimMinutes(int m) => _setDimMode(true, m);

  // —— 检查更新 ——

  /// 取本机版本名/版本号，并在启动后静默检查一次（仅在有新版本时弹窗）
  Future<void> _initVersion() async {
    try {
      final v =
          await _channel.invokeMethod<Map<Object?, Object?>>('getAppVersion');
      if (!mounted) return;
      setState(() {
        _localVersion = (v?['version'] as String?) ?? '1.0.0';
        _localVersionCode = (v?['versionCode'] as int?) ?? 1;
        _localAbi = (v?['abi'] as String?) ?? '';
      });
    } catch (_) {}
    _checkUpdate(silent: true);
  }

  /// 依次尝试 _updateInfoUrls 中的地址（API 优先，镜像/raw 兜底），
  /// 任一成功即返回 (版本信息, 数据源域名)；全部失败返回 null
  Future<(Map<String, dynamic>, String)?> _fetchUpdateInfo() async {
    for (final url in _updateInfoUrls) {
      final info = await _fetchJson(url);
      if (info != null) return (info, Uri.parse(url).host);
    }
    return null;
  }

  /// 拉取单个 URL 的 JSON；任何异常（无网/超时/解析失败）都返回 null
  Future<Map<String, dynamic>?> _fetchJson(String urlStr) async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);
      // 加时间戳参数绕过 CDN 缓存，确保拿到最新版本信息
      final base = Uri.parse(urlStr);
      final uri = base.replace(queryParameters: <String, String>{
        ...base.queryParameters,
        't': DateTime.now().millisecondsSinceEpoch.toString(),
      });
      final req = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = await resp
          .transform(const Utf8Decoder())
          .join()
          .timeout(const Duration(seconds: 6));
      // GitHub Contents API 返回 base64 包装的文件内容，需先解码
      if (base.host == 'api.github.com') {
        final meta = jsonDecode(body) as Map<String, dynamic>;
        final content = meta['content']?.toString() ?? '';
        if (content.isEmpty) return null;
        final decoded =
            utf8.decode(base64Decode(content.replaceAll('\n', '')));
        return jsonDecode(decoded) as Map<String, dynamic>;
      }
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    } finally {
      client?.close();
    }
  }

  /// 检查更新：silent=true 时仅在有新版本时弹窗，最新/失败不打扰（用于启动自动检查）；
  /// 手动检查时显示加载动画，进行中不可重复点击
  Future<void> _checkUpdate({bool silent = false}) async {
    if (_checkingUpdate) return;
    if (!silent) setState(() => _checkingUpdate = true);
    try {
      final result = await _fetchUpdateInfo();
      if (!mounted) return;
      if (result == null) {
        if (!silent) _toast('检查更新失败，请稍后重试');
        return;
      }
      final (info, source) = result;
      final remoteCode =
          info['versionCode'] is int ? info['versionCode'] as int : -1;
      if (remoteCode > _localVersionCode) {
        _showUpdateDialog(info);
      } else if (!silent) {
        _toast('已是最新版本 (v$_localVersion)');
      }
    } finally {
      if (!silent && mounted) setState(() => _checkingUpdate = false);
    }
  }

  void _showUpdateDialog(Map<String, dynamic> info) {
    final version = (info['version']?.toString() ?? '').trim();
    final notes = (info['notes']?.toString() ?? '').trim();
    final mandatory = info['mandatory'] == true;
    showDialog(
      context: context,
      barrierDismissible: !mandatory,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF10142A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF00F0FF).withOpacity(0.4)),
        ),
        title: Text(
          '发现新版本${version.isNotEmpty ? ' v$version' : ''}',
          style: const TextStyle(
            color: Color(0xFF00F0FF),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            notes.isNotEmpty ? notes : '有可用更新，建议前往更新。',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        actions: [
          if (!mandatory)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  const Text('暂不', style: TextStyle(color: Colors.white38)),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startInAppUpdate(info);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('立即更新',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    try {
      await _channel.invokeMethod<void>('openBrowser', {'url': url});
    } catch (_) {}
  }

  /// 应用内更新：下载对应架构的 APK 并显示进度，完成后调起系统安装器。
  /// 下载源按顺序尝试（GitHub Releases 资产 → jsDelivr 仓库镜像等），
  /// 任一成功即用；若远程未提供下载模板 / 无法解析本机架构，则回退到打开发布页。
  Future<void> _startInAppUpdate(Map<String, dynamic> info) async {
    if (_downloading) return; // 下载进行中，忽略重复点击
    final hasAbi = _localAbi.isNotEmpty && _localAbi != 'unknown';
    // 收集候选下载模板：downloadTemplates（列表，按序尝试）+ downloadTemplate（单个，向后兼容）
    final templates = <String>[];
    final list = info['downloadTemplates'];
    if (list is List) {
      for (final e in list) {
        final s = e?.toString() ?? '';
        if (s.isNotEmpty) templates.add(s);
      }
    }
    final single = info['downloadTemplate']?.toString() ?? '';
    if (single.isNotEmpty && !templates.contains(single)) templates.add(single);

    final dlUrls = <String>[];
    for (final t in templates) {
      if (!t.contains('{abi}')) continue;
      if (!hasAbi) continue;
      final u = t.replaceAll('{abi}', _localAbi);
      if (!dlUrls.contains(u)) dlUrls.add(u);
    }
    if (dlUrls.isEmpty) {
      // 没有可直接下载的地址，回退到浏览器打开发布页
      _openUrl((info['url']?.toString() ?? _updateInfoUrls.last).trim());
      return;
    }
    final fallbackUrl = (info['url']?.toString() ?? _updateInfoUrls.last).trim();

    setState(() {
      _downloading = true;
      _cancelDownload = false;
      _downloadProgress = 0;
    });
    _downloadDialogOpen = true;
    _showDownloadDialog(info['mandatory'] == true);
    try {
      final dir = await _channel.invokeMethod<String>('getApkDir');
      if (dir == null) throw Exception('无法获取下载目录');
      final filePath = '$dir/keep-screen-update.apk';
      await _downloadApk(dlUrls, filePath, onProgress: (p) {
        if (mounted) setState(() => _downloadProgress = p);
      });
      if (_cancelDownload) return;
      // 下载完成，调起系统安装器
      final status =
          await _channel.invokeMethod<String>('installApk', {'path': filePath});
      if (status == 'need_permission') {
        _toast('请先在系统设置中允许“安装未知应用”，再重试更新');
      } else if (status == 'error') {
        _toast('安装失败，已为你打开发布页手动下载');
        _openUrl(fallbackUrl);
      }
    } catch (e) {
      if (!_cancelDownload) {
        _toast('下载失败，已为你打开发布页：${_shortErr(e)}');
        _openUrl(fallbackUrl);
      }
    } finally {
      if (mounted) {
        // 关闭进度弹窗（若仍打开，避免取消后重复 pop）
        if (_downloadDialogOpen) {
          Navigator.of(context, rootNavigator: true).pop();
          _downloadDialogOpen = false;
        }
        _downloading = false;
        _downloadProgress = 0;
        setState(() {});
      }
    }
  }

  String _shortErr(Object e) {
    final s = e.toString();
    return s.length > 60 ? '${s.substring(0, 60)}…' : s;
  }

  /// 流式下载 APK 到 filePath，回调 onProgress（0~1，或 -1 表示未知总大小）。
  /// 跟随重定向（GitHub Release 资产会 302 到对象存储）。
  /// urls 按顺序尝试：连接失败 / 响应头超时 / 正文停滞超 20 秒 / 非 200，
  /// 都会自动切换下一个源；全部失败才抛出最后一个错误。
  Future<void> _downloadApk(
    List<String> urls,
    String filePath, {
    required void Function(double progress) onProgress,
  }) async {
    Object? lastError;
    for (final url in urls) {
      try {
        await _downloadFrom(url, filePath, onProgress);
        return; // 下载成功
      } catch (e) {
        if (_cancelDownload) rethrow;
        lastError = e; // 该源失败，尝试下一个
      }
    }
    throw lastError ?? Exception('所有下载源均失败');
  }

  /// 从单个 url 下载 APK。响应头最长等 12 秒；正文超过 20 秒无数据视为停滞并抛错。
  Future<void> _downloadFrom(
    String url,
    String filePath,
    void Function(double progress) onProgress,
  ) async {
    HttpClient? client;
    HttpClientResponse? resp;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      Uri uri = Uri.parse(url);
      for (var hop = 0; hop < 6; hop++) {
        final req = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 10));
        resp = await req.close().timeout(const Duration(seconds: 12));
        if ((resp.statusCode == 301 ||
                resp.statusCode == 302 ||
                resp.statusCode == 303) &&
            hop < 5) {
          final loc = resp.headers.value(HttpHeaders.locationHeader);
          await resp.drain();
          if (loc == null) throw Exception('重定向缺少 Location');
          uri = uri.resolve(loc);
          continue;
        }
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }
        break;
      }

      final total = resp!.contentLength;
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      // 停滞检测：两次数据之间超过 20 秒即认为该源不通，抛错切换下一个源
      final watched = resp.timeout(
        const Duration(seconds: 20),
        onTimeout: (sink) {
          sink.addError(Exception('下载停滞（20 秒无数据）'));
          sink.close();
        },
      );
      await for (final chunk in watched) {
        if (_cancelDownload) {
          await sink.close();
          await file.delete();
          return;
        }
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          onProgress(received / total);
        } else {
          onProgress(-1); // 不确定进度
        }
      }
      await sink.close();
    } finally {
      client?.close();
    }
  }

  /// 下载进度弹窗：线性进度条 + 百分比 +（非强制时）取消按钮
  void _showDownloadDialog(bool mandatory) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setInner) {
          return AlertDialog(
            backgroundColor: const Color(0xFF10142A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: const Color(0xFF00F0FF).withOpacity(0.4)),
            ),
            title: const Text(
              '正在更新',
              style: TextStyle(
                color: Color(0xFF00F0FF),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _downloadProgress < 0 ? null : _downloadProgress,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F0FF)),
                  minHeight: 8,
                ),
                const SizedBox(height: 12),
                Text(
                  _downloadProgress < 0
                      ? '正在下载更新包…'
                      : '下载进度 ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            actions: [
              if (!mandatory)
                TextButton(
                  onPressed: () {
                    _cancelDownload = true;
                    _downloadDialogOpen = false;
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('取消',
                      style: TextStyle(color: Colors.white38)),
                ),
            ],
          );
        },
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = _isOn ? const Color(0xFF00F0FF) : const Color(0xFF2A2F45);
    final glow = _isOn
        ? [
            BoxShadow(
              color: const Color(0xFF00F0FF).withOpacity(0.55),
              blurRadius: 38,
              spreadRadius: 4,
            ),
            BoxShadow(
              color: const Color(0xFF7A5CFF).withOpacity(0.35),
              blurRadius: 60,
              spreadRadius: 2,
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withOpacity(0.6),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ];

    return Scaffold(
      backgroundColor: const Color(0xFF070B1E),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.2,
            colors: [Color(0xFF141A3A), Color(0xFF070B1E)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              children: [
                // 顶部标题
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF00F0FF), Color(0xFF7A5CFF)],
                  ).createShader(bounds),
                  child: const Text(
                    '常亮小助手',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'SCREEN · ALWAYS · ON',
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 4,
                    color: Colors.cyanAccent,
                  ),
                ),
                const SizedBox(height: 40),

                // 中央发光开关（手动总开关）
                GestureDetector(
                  onTap: _toggleManual,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _manualOn
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF00F0FF), Color(0xFF7A5CFF)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFF1B2138), Color(0xFF10142A)],
                            ),
                      boxShadow: glow,
                      border: Border.all(
                        color: _manualOn
                            ? Colors.cyanAccent.withOpacity(0.9)
                            : Colors.white.withOpacity(0.08),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      _isOn ? Icons.lightbulb : Icons.lightbulb_outline,
                      size: 68,
                      color: _isOn ? Colors.black : Colors.white54,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // 状态文字
                Text(
                  _statusText(),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _isOn
                        ? const Color(0xFF00F0FF)
                        : Colors.white70,
                    shadows: _isOn
                        ? [
                            Shadow(
                              color: const Color(0xFF00F0FF).withOpacity(0.8),
                              blurRadius: 14,
                            )
                          ]
                        : null,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (_remainingSeconds > 0 && _manualOn)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${_formatRemaining(_remainingSeconds)} 后自动关闭',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.amberAccent,
                      ),
                    ),
                  ),
                const SizedBox(height: 28),

                // 设置卡片
                _SettingsCard(
                  timerMinutes: _timerMinutes,
                  onTimer: _setTimer,
                  dimEnabled: _dimEnabled,
                  dimMinutes: _dimMinutes,
                  onDimEnabled: _setDimEnabled,
                  onDimMinutes: _setDimMinutes,
                  chargeMode: _chargeMode,
                  charging: _charging,
                  onChargeMode: _setChargeMode,
                  foregroundMode: _foregroundMode,
                  usageGranted: _usageGranted,
                  targetAppName: _targetAppName,
                  targetAppIcon: _targetAppIcon,
                  targetPackage: _targetPackage,
                  onForegroundMode: _setForegroundMode,
                  onPickApp: _pickApp,
                  onOpenPermissions: _openPermissions,
                  onCheckUpdate: () => _checkUpdate(),
                  localVersion: _localVersion,
                  checkingUpdate: _checkingUpdate,
                ),
                const SizedBox(height: 16),
                Text(
                  _dimmed
                      ? '已降低亮度以防烧屏 · 取消常亮或关闭开关即恢复'
                      : '常亮时注意电量与烧屏 · 用完即关',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusText() {
    if (!_isOn) return '屏幕将自动息屏';
    final parts = <String>[];
    if (_manualOn) parts.add('手动');
    if (_charging && _chargeMode) parts.add('充电中');
    if (_foregroundMode && _targetPackage.isNotEmpty) parts.add('前台App');
    final reason = parts.isEmpty ? '常亮中' : parts.join(' · ');
    return '屏幕常亮中（$reason）';
  }

  String _formatRemaining(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    if (m > 0) return '$m 分 $sec 秒';
    return '$sec 秒';
  }
}

/// 设置卡片：定时关闭 / 充电时常亮 / 指定 App 前台时常亮
class _SettingsCard extends StatelessWidget {
  final int timerMinutes;
  final ValueChanged<int> onTimer;
  final bool dimEnabled;
  final int dimMinutes;
  final ValueChanged<bool> onDimEnabled;
  final ValueChanged<int> onDimMinutes;
  final bool chargeMode;
  final bool charging;
  final ValueChanged<bool> onChargeMode;
  final bool foregroundMode;
  final bool usageGranted;
  final String targetAppName;
  final String? targetAppIcon;
  final String targetPackage;
  final ValueChanged<bool> onForegroundMode;
  final VoidCallback onPickApp;
  final VoidCallback onOpenPermissions;
  final VoidCallback onCheckUpdate;
  final String localVersion;
  final bool checkingUpdate;

  const _SettingsCard({
    required this.timerMinutes,
    required this.onTimer,
    required this.dimEnabled,
    required this.dimMinutes,
    required this.onDimEnabled,
    required this.onDimMinutes,
    required this.chargeMode,
    required this.charging,
    required this.onChargeMode,
    required this.foregroundMode,
    required this.usageGranted,
    required this.targetAppName,
    required this.targetAppIcon,
    required this.targetPackage,
    required this.onForegroundMode,
    required this.onPickApp,
    required this.onOpenPermissions,
    required this.onCheckUpdate,
    required this.localVersion,
    required this.checkingUpdate,
  });

  static const List<int> _timerOptions = [0, 5, 10, 30, 60];

  /// 由 base64 PNG 渲染应用图标；无图标或解析失败时回退为默认图标
  static Widget _appIcon(String? base64) {
    if (base64 != null && base64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(base64),
          width: 24,
          height: 24,
          errorBuilder: (_, __, ___) => const Icon(Icons.android,
              size: 24, color: Colors.white38),
        );
      } catch (_) {}
    }
    return const Icon(Icons.android, size: 24, color: Colors.white38);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('自动关闭设置',
              style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('定时关闭（手动开启后生效）',
              style: TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: DropdownButton<int>(
              value: timerMinutes,
              isExpanded: true,
              dropdownColor: const Color(0xFF10142A),
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00F0FF)),
              style: const TextStyle(color: Colors.white, fontSize: 15),
              items: _timerOptions.map((m) {
                return DropdownMenuItem<int>(
                  value: m,
                  child: Text(m == 0 ? '关闭' : '$m 分钟'),
                );
              }).toList(),
              onChanged: (v) => onTimer(v ?? 0),
            ),
          ),

          const Divider(height: 24, color: Colors.white12),

          // 充电时常亮
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('充电时常亮', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              charging ? '正在充电' : '未充电',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            value: chargeMode,
            activeColor: const Color(0xFF00F0FF),
            onChanged: onChargeMode,
          ),

          const Divider(height: 16, color: Colors.white12),

          // 指定 App 前台时常亮
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('指定 App 前台时常亮',
                style: TextStyle(color: Colors.white)),
            subtitle: foregroundMode
                ? Row(
                    children: [
                      _appIcon(targetAppIcon),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          targetAppName.isNotEmpty
                              ? targetAppName
                              : (targetPackage.isNotEmpty
                                  ? targetPackage
                                  : '未选择应用'),
                          style: const TextStyle(
                              color: Color(0xFF00F0FF), fontSize: 12),
                        ),
                      ),
                    ],
                  )
                : const Text('该 App 在前台时保持常亮',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
            value: foregroundMode,
            activeColor: const Color(0xFF00F0FF),
            onChanged: onForegroundMode,
          ),
          if (foregroundMode)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: ElevatedButton.icon(
                onPressed: onPickApp,
                icon: const Icon(Icons.apps, size: 18),
                label: Text(targetAppName.isNotEmpty ? '更换应用' : '选择应用'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B2138),
                  foregroundColor: const Color(0xFF00F0FF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          if (foregroundMode && !usageGranted)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '需授予“使用情况访问”权限才能检测前台 App，已为你打开设置页。',
                style: TextStyle(color: Colors.amberAccent, fontSize: 12),
              ),
            ),

          const Divider(height: 24, color: Colors.white12),

          // 定时降低亮度（防烧屏）
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('定时降低亮度（防烧屏）',
                style: TextStyle(color: Colors.white)),
            subtitle: const Text('常亮持续到点后自动调暗背光，关闭开关或取消常亮即恢复',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            value: dimEnabled,
            activeColor: const Color(0xFF00F0FF),
            onChanged: onDimEnabled,
          ),
          if (dimEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: DropdownButton<int>(
                  value: dimMinutes,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF10142A),
                  underline: const SizedBox.shrink(),
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF00F0FF)),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  items: List.generate(30, (i) => i + 1)
                      .map((m) => DropdownMenuItem<int>(
                            value: m,
                            child: Text('$m 分钟'),
                          ))
                      .toList(),
                  onChanged: (v) => onDimMinutes(v ?? dimMinutes),
                ),
              ),
            ),

          const Divider(height: 24, color: Colors.white12),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onOpenPermissions,
              icon: const Icon(Icons.verified_user, size: 18),
              label: const Text('权限设置（电池优化 / 悬浮窗 / 使用情况）'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF00F0FF),
                side: const BorderSide(color: Color(0xFF00F0FF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const Divider(height: 24, color: Colors.white12),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_alt,
                color: Color(0xFF00F0FF), size: 22),
            title: const Text('检查更新', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              checkingUpdate ? '正在检查更新…' : '当前版本 v$localVersion',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            trailing: checkingUpdate
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF00F0FF),
                    ),
                  )
                : const Icon(Icons.chevron_right, color: Colors.white38),
            onTap: checkingUpdate ? null : onCheckUpdate,
          ),
        ],
      ),
    );
  }
}

/// 应用选择器：从原生取已装应用列表，支持搜索
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key});

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  static const MethodChannel _channel = MethodChannel(_channelName);
  List<_AppInfo> _all = [];
  List<_AppInfo> _filtered = [];
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(_filter);
  }

  Future<void> _load() async {
    try {
      final raw = await _channel.invokeMethod<String>('getInstalledApps') ?? '[]';
      final list = (jsonDecode(raw) as List)
          .map((e) => _AppInfo(
                name: e['name'] as String,
                package: e['package'] as String,
                icon: e['icon'] as String?,
              ))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _all = list;
        _filtered = list;
      });
    } catch (e) {
      setState(() => _filtered = []);
    }
  }

  void _filter() {
    final t = _q.text.toLowerCase();
    setState(() {
      _filtered = _all
          .where((a) =>
              a.name.toLowerCase().contains(t) ||
              a.package.toLowerCase().contains(t))
          .toList();
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B1E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('选择应用', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _q,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '搜索应用名称或包名',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(
                    child: Text('加载中或无可启动应用',
                        style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final a = _filtered[i];
                      return ListTile(
                        leading: _SettingsCard._appIcon(a.icon),
                        title: Text(a.name,
                            style: const TextStyle(color: Colors.white)),
                        subtitle: Text(a.package,
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 12)),
                        onTap: () => Navigator.pop(context,
                            {'name': a.name, 'package': a.package, 'icon': a.icon}),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AppInfo {
  final String name;
  final String package;
  final String? icon;
  _AppInfo({required this.name, required this.package, this.icon});
}
