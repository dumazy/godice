// Example app for godice_universal_ble.
//
// Scans for GoDice, connects to the one you tap, shows the rolled value and
// lets you switch die type, read battery/colour and control the LEDs. Every
// roll is also printed with debugPrint so it shows up in `flutter run` logs.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:godice/godice.dart';
import 'package:godice_universal_ble/godice_universal_ble.dart';

void main() => runApp(const GoDiceExampleApp());

class GoDiceExampleApp extends StatelessWidget {
  const GoDiceExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GoDice',
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.indigo,
      brightness: Brightness.dark,
      useMaterial3: true,
    ),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GoDiceScanner _scanner = GoDiceScanner(manageScan: true);
  final Map<String, BleDevice> _found = <String, BleDevice>{};
  StreamSubscription<BleDevice>? _scanSub;
  String? _error;

  GoDice? _die;
  StreamSubscription<GoDiceMessage>? _messageSub;
  StreamSubscription<bool>? _linkSub;
  bool _connecting = false;
  bool _ledsOn = false;
  PositionMessage? _lastPosition;
  bool _rolling = false;
  int? _battery;

  bool get _scanning => _scanSub != null;

  @override
  void dispose() {
    _scanSub?.cancel();
    _disconnect();
    super.dispose();
  }

  void _toggleScan() {
    if (_scanning) {
      _scanSub?.cancel();
      setState(() => _scanSub = null);
      return;
    }
    setState(() {
      _error = null;
      _found.clear();
    });
    _scanSub = _scanner.discover().listen(
      (d) => setState(() => _found[d.deviceId] = d),
      onError: (Object e) => setState(() {
        _error = e.toString();
        _scanSub = null;
      }),
      onDone: () => setState(() => _scanSub = null),
    );
    setState(() {});
  }

  Future<void> _connect(BleDevice device) async {
    _scanSub?.cancel();
    _scanSub = null;
    final die = GoDiceUniversalBle.fromDevice(device);
    setState(() {
      _connecting = true;
      _error = null;
      _die = die;
    });
    try {
      _linkSub = die.connectionState.listen((up) {
        if (!up && mounted) {
          debugPrint('GoDice ${die.name} disconnected');
          _disconnect();
        }
      });
      _messageSub = die.messages.listen(_onMessage);
      await die.connect();
      debugPrint('Connected to ${die.name}');
      _battery = await die.getBatteryLevel();
      await die.getColor();
      await die.setLeds(die.color?.rgb ?? RgbColor.white);
      _ledsOn = true;
    } on Object catch (e) {
      debugPrint('Connect failed: $e');
      _error = e.toString();
      await _disconnect();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _onMessage(GoDiceMessage message) {
    switch (message) {
      case RollStartMessage():
        debugPrint('rolling...');
        setState(() => _rolling = true);
      case PositionMessage():
        debugPrint(
          '${message.kind.name} ${message.value} '
          '(${message.dieType.name}, xyz ${message.xyz})',
        );
        setState(() {
          _rolling = false;
          _lastPosition = message;
        });
      case BatteryLevelMessage(:final level):
        setState(() => _battery = level);
      case DiceColorMessage() || UnknownMessage():
        setState(() {});
    }
  }

  Future<void> _disconnect() async {
    final die = _die;
    await _messageSub?.cancel();
    await _linkSub?.cancel();
    _messageSub = null;
    _linkSub = null;
    if (die != null) {
      if (die.isConnected) {
        try {
          await die.ledsOff();
        } on Object {
          // Link already gone.
        }
      }
      await die.dispose();
    }
    if (mounted) {
      setState(() {
        _die = null;
        _lastPosition = null;
        _rolling = false;
        _battery = null;
        _ledsOn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final die = _die;
    return Scaffold(
      appBar: AppBar(
        title: Text(die == null ? 'GoDice' : die.name ?? 'GoDice'),
        actions: <Widget>[
          if (die != null)
            IconButton(
              tooltip: 'Disconnect',
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
            ),
        ],
      ),
      body: die == null ? _buildScanView() : _buildDieView(die),
    );
  }

  Widget _buildScanView() {
    final devices = _found.values.toList()
      ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _connecting ? null : _toggleScan,
            icon: Icon(_scanning ? Icons.stop : Icons.search),
            label: Text(_scanning ? 'Stop scanning' : 'Scan for dice'),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_scanning) const LinearProgressIndicator(),
        if (_connecting)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Connecting...'),
          ),
        Expanded(
          child: devices.isEmpty
              ? const Center(child: Text('Shake a die to wake it up.'))
              : ListView(
                  children: <Widget>[
                    for (final d in devices)
                      ListTile(
                        leading: _ColorDot(
                          GoDiceDeviceName.tryParse(d.name)?.color,
                        ),
                        title: Text(d.name ?? d.deviceId),
                        subtitle: Text('${d.rssi ?? '?'} dBm  ${d.deviceId}'),
                        onTap: _connecting ? null : () => _connect(d),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildDieView(GoDice die) {
    final position = _lastPosition;
    final theme = Theme.of(context);
    final String big;
    if (_rolling) {
      big = '…';
    } else if (position == null) {
      big = '?';
    } else if (die.dieType == DieType.d10x) {
      big = position.value.toString().padLeft(2, '0');
    } else {
      big = '${position.value}';
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              _ColorDot(die.color, label: die.color?.name ?? 'colour ?'),
              Text(_battery == null ? 'battery ?' : 'battery $_battery%'),
              DropdownButton<DieType>(
                value: die.dieType,
                onChanged: (t) => setState(() => die.dieType = t!),
                items: <DropdownMenuItem<DieType>>[
                  for (final t in DieType.values)
                    DropdownMenuItem<DieType>(
                      value: t,
                      child: Text(t.name.toUpperCase()),
                    ),
                ],
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    big,
                    style: theme.textTheme.displayLarge?.copyWith(
                      fontSize: 140,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _rolling
                        ? 'rolling'
                        : position == null
                        ? 'Roll the die'
                        : switch (position.kind) {
                            StabilityKind.stable => 'rolled',
                            StabilityKind.fakeStable => 'paused mid-roll',
                            StabilityKind.tiltStable => 'tilted',
                            StabilityKind.moveStable => 'moved, not rolled',
                          },
                    style: theme.textTheme.titleMedium,
                  ),
                  if (position != null)
                    Text(
                      'xyz ${position.xyz}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => unawaited(
                  die.getBatteryLevel().catchError((Object _) => _battery ?? 0),
                ),
                child: const Text('Battery'),
              ),
              OutlinedButton(
                onPressed: () {
                  _ledsOn = !_ledsOn;
                  unawaited(
                    _ledsOn
                        ? die.setLeds(die.color?.rgb ?? RgbColor.white)
                        : die.ledsOff(),
                  );
                  setState(() {});
                },
                child: Text(_ledsOn ? 'LEDs off' : 'LEDs on'),
              ),
              OutlinedButton(
                onPressed: () => unawaited(
                  die.pulseLed(color: die.color?.rgb ?? RgbColor.white),
                ),
                child: const Text('Pulse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color, {this.label});

  final DiceColor? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final rgb = color?.rgb;
    final dot = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: rgb == null
            ? Colors.grey
            : color == DiceColor.black
            ? Colors.black
            : Color.fromARGB(255, rgb.r, rgb.g, rgb.b),
        border: Border.all(color: Colors.grey.shade600),
      ),
    );
    if (label == null) return dot;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[dot, const SizedBox(width: 8), Text(label!)],
    );
  }
}
