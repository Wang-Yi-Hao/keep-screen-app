import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 常亮小助手 —— V2（仅安卓）
/// 科技风 UI：深色背景 + 霓虹青发光质感。
/// V2 新增：定时关闭 / 充电时常亮 / 指定 App 前台时常亮。
/// 通过 MethodChannel 调原生，EventChannel 接收实时状态。

const String _channelName = 'com.keepscreen.app/keep';
const String _eventName = 'com.keepscreen.app/events';

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

/// 首次启动权限引导页：先授予必要权限（电池优化白名单等）再进入应用。
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
                const Text('先授予以下权限，应用才能稳定保持屏幕常亮',
                    style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 24),
                _row(
                  icon: Icons.battery_charging_full,
                  title: '电池优化白名单（必选）',
                  subtitle: '加入后前台服务不易被系统回收，常亮更可靠',
                  granted: _batteryOpt,
                  required_: true,
                  onTap: _openBattery,
                ),
                _row(
                  icon: Icons.layers,
                  title: '悬浮窗权限（必选）',
                  subtitle: '开启后 App 退到后台仍可保持常亮',
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
                    onPressed: (_batteryOpt && _overlay) ? _enter : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white12,
                      disabledForegroundColor: Colors.white38,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('进入应用',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 12),
                if (!_batteryOpt || !_overlay)
                  Center(
                    child: TextButton(
                      onPressed: _enter,
                      child: const Text('暂不设置，直接进入',
                          style: TextStyle(color: Colors.white54)),
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

  // —— UI 侧状态 ——
  bool _needsOverlayPermission = false;
  String _targetAppName = '';
  String? _targetAppIcon; // 已选应用图标（base64），用于卡片展示
  bool _usageGranted = true;
  bool _pendingForegroundEnable = false; // 等待用户从设置授权后补开

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _events.receiveBroadcastStream().listen(_onState);
    _loadInitialState();
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
      if (_targetPackage.isNotEmpty && _targetAppName.isEmpty) {
        // 名称在选应用时记录，这里仅保留包名
      }
    });
  }

  bool _asBool(dynamic v) => v == true;
  int _asInt(dynamic v) => (v is int) ? v : -1;

  // —— 命令封装 ——
  Future<void> _toggleManual() async {
    if (_manualOn) {
      await _channel.invokeMethod<void>('stop');
    } else {
      // 悬浮窗为首次必选权限；若用户事后撤销，这里重新引导授予
      final bool hasPerm =
          await _channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      if (!hasPerm) {
        await _channel.invokeMethod<void>('openOverlaySettings');
        setState(() => _needsOverlayPermission = true);
        return;
      }
      await _channel.invokeMethod<void>('start');
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
                ),
                const SizedBox(height: 16),
                Text(
                  _needsOverlayPermission
                      ? '已打开设置，请允许“显示在其他应用上”后返回点击开关'
                      : '常亮时注意电量与烧屏 · 用完即关',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _needsOverlayPermission
                        ? Colors.amberAccent
                        : Colors.white38,
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

  const _SettingsCard({
    required this.timerMinutes,
    required this.onTimer,
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
