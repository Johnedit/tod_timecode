import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const TimecodeApp());
}

class TimecodeApp extends StatelessWidget {
  const TimecodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timecode Slate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(surface: Colors.black),
      ),
      home: const TimecodeScreen(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class TimecodeScreen extends StatefulWidget {
  const TimecodeScreen({super.key});

  @override
  State<TimecodeScreen> createState() => _TimecodeScreenState();
}

class _TimecodeScreenState extends State<TimecodeScreen> {
  // Supported frame rates
  static const List<double> kFrameRates = [
    23.976, 24.0, 25.0, 29.97, 30.0, 48.0, 50.0, 59.94, 60.0
  ];
  static const List<String> kFrameRateLabels = [
    '23.976', '24', '25', '29.97', '30', '48', '50', '59.94', '60'
  ];

  double _fps = 25.0;
  Timer _timer = Timer(Duration.zero, () {});
  late _TimecodeValue _tc;

  @override
  void initState() {
    super.initState();
    _tc = _TimecodeValue.now(_fps);
    _startTimer();
  }

  void _startTimer() {
    _timer.cancel();
    // Tick at roughly 2× frame interval for smooth display
    final intervalMs = (500 / _fps).floor().clamp(8, 500);
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      setState(() => _tc = _TimecodeValue.now(_fps));
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _openSettings() {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => _SettingsDialog(
        currentFps: _fps,
        frameRates: kFrameRates,
        labels: kFrameRateLabels,
        onSelected: (fps) {
          setState(() {
            _fps = fps;
            _tc = _TimecodeValue.now(_fps);
          });
          _startTimer();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main timecode display – centred
          Center(
            child: _TimecodeDisplay(tc: _tc),
          ),

          // Settings cog – top-right
          Positioned(
            top: 12,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Color(0x99FFFFFF), size: 28),
              onPressed: _openSettings,
              tooltip: 'Frame rate settings',
            ),
          ),

          // fps label – bottom-right
          Positioned(
            bottom: 10,
            right: 16,
            child: Text(
              '${kFrameRateLabels[kFrameRates.indexOf(_fps)]} fps',
              style: const TextStyle(
                color: Color(0x66FFFFFF),
                fontSize: 14,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timecode value model
// ─────────────────────────────────────────────────────────────────────────────

class _TimecodeValue {
  final int hh, mm, ss, ff;

  const _TimecodeValue(this.hh, this.mm, this.ss, this.ff);

  factory _TimecodeValue.now(double fps) {
    final now = DateTime.now();
    final ms = now.millisecond + now.microsecond / 1000.0;
    // Frame = floor(ms / (1000 / fps)), capped at fps-1
    final frame = (ms * fps / 1000).floor().clamp(0, fps.floor() - 1);
    return _TimecodeValue(now.hour, now.minute, now.second, frame);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Timecode display widget
// ─────────────────────────────────────────────────────────────────────────────

class _TimecodeDisplay extends StatelessWidget {
  final _TimecodeValue tc;

  const _TimecodeDisplay({required this.tc});

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final screenH = MediaQuery.of(context).size.height;

    // Fill ~90% of the shorter dimension so it works on any device
    final availH = screenH * 0.75;
    final availW = screenW * 0.96;

    // HH:MM:SS:FF → 8 digits + 3 separators + 3 separator gaps
    // We size so the full string fits width; cap by height too.
    // Each digit cell = digitW, each ':' cell = sepW
    const digitCount = 8;
    const sepCount = 3;
    const sepRatio = 0.45; // separator width relative to digit width
    const digitAspect = 0.65; // rough width:height of a monospace digit

    // Solve: digitCount*dW + sepCount*sepRatio*dW = availW
    //        dH = dW / digitAspect
    //        dH <= availH
    final dWfromWidth = availW / (digitCount + sepCount * sepRatio);
    final dWfromHeight = availH * digitAspect;
    final dW = dWfromHeight < dWfromWidth ? dWfromHeight : dWfromWidth;
    final fontSize = dW / digitAspect;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _DigitPair(value: tc.hh, fontSize: fontSize),
        _Separator(fontSize: fontSize),
        _DigitPair(value: tc.mm, fontSize: fontSize),
        _Separator(fontSize: fontSize),
        _DigitPair(value: tc.ss, fontSize: fontSize),
        _Separator(fontSize: fontSize, isFrame: true),
        _DigitPair(value: tc.ff, fontSize: fontSize),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A two-digit, fixed-width, monospace pair
// Each digit sits in its own fixed-width box so nothing jiggles.
// ─────────────────────────────────────────────────────────────────────────────

class _DigitPair extends StatelessWidget {
  final int value;
  final double fontSize;

  const _DigitPair({required this.value, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final s = value.clamp(0, 99).toString().padLeft(2, '0');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FixedDigit(char: s[0], fontSize: fontSize),
        _FixedDigit(char: s[1], fontSize: fontSize),
      ],
    );
  }
}

class _FixedDigit extends StatelessWidget {
  final String char;
  final double fontSize;

  const _FixedDigit({required this.char, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    // cellWidth: we size to the widest digit ('0') plus a tiny side pad.
    // Using a TextPainter to measure '0' would be ideal; a fixed ratio is
    // robust and avoids layout passes.  Roboto Mono / Courier digits
    // are ~0.60–0.62× their point size in width.
    final cellW = fontSize * 0.62;
    return SizedBox(
      width: cellW,
      child: Text(
        char,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier', // guaranteed monospace on both platforms
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: Colors.white,
          height: 1.0,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Colon separator  (slightly smaller, dimmed; dot for frame boundary)
// ─────────────────────────────────────────────────────────────────────────────

class _Separator extends StatelessWidget {
  final double fontSize;
  final bool isFrame; // frame separator gets a different colour

  const _Separator({required this.fontSize, this.isFrame = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fontSize * 0.30,
      child: Text(
        ':',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier',
          fontSize: fontSize * 0.80,
          fontWeight: FontWeight.w900,
          color: isFrame ? const Color(0xFFFF6600) : const Color(0xCCFFFFFF),
          height: 1.0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsDialog extends StatelessWidget {
  final double currentFps;
  final List<double> frameRates;
  final List<String> labels;
  final ValueChanged<double> onSelected;

  const _SettingsDialog({
    required this.currentFps,
    required this.frameRates,
    required this.labels,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Frame Rate',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(frameRates.length, (i) {
                final fps = frameRates[i];
                final selected = fps == currentFps;
                return GestureDetector(
                  onTap: () {
                    onSelected(fps);
                    Navigator.of(context).pop();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? Colors.white : const Color(0xFF444444),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.black : Colors.white,
                      ),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            const Text(
              'Tip: hold the slate steady for 1–2 seconds so all cameras capture the same frame number.',
              style: TextStyle(color: Color(0x88FFFFFF), fontSize: 12),
            ),
            const SizedBox(height: 20),
            const Divider(color: Color(0xFF2A2A2A)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final uri = Uri.parse('https://YOUR-PRIVACY-POLICY-URL-HERE');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text(
                'Privacy Policy',
                style: TextStyle(
                  color: Color(0xFFFF6600),
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFFFF6600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}