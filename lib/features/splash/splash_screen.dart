import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/database/database_helper.dart';
import '../../core/theme/brand.dart';

/// Branded opening screen. Shows the Urban Thread logo while the database
/// opens, then fades into [child]. Stays at least [minDuration] so the
/// animation is seen, but never blocks longer than the startup work.
class SplashGate extends StatefulWidget {
  final Widget child;
  final Duration minDuration;

  const SplashGate({
    super.key,
    required this.child,
    this.minDuration = const Duration(milliseconds: 1600),
  });

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final Animation<double> _logo = CurvedAnimation(
    parent: _anim,
    curve: const Interval(0, 0.6, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _line = CurvedAnimation(
    parent: _anim,
    curve: const Interval(0.35, 1, curve: Curves.easeInOutCubic),
  );

  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      await Future.wait([
        DatabaseHelper.instance.database, // open + migrate before first use
        Future.delayed(widget.minDuration),
      ]);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      child: _ready ? widget.child : _splash(context),
    );
  }

  Widget _splash(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final logoWidth = (width * 0.72).clamp(200.0, 420.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        key: const ValueKey('splash'),
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _logo,
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.0).animate(_logo),
                  child: Image.asset(
                    Brand.logoOnDark,
                    width: logoWidth,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(height: 36),
              // Gold "thread" that draws across while loading.
              SizedBox(
                width: logoWidth * 0.5,
                height: 2,
                child: AnimatedBuilder(
                  animation: _line,
                  builder: (context, _) => Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: _line.value,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Brand.gold,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Could not open the shop database:\n$_error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Brand.cream),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Brand.cream,
                    side: const BorderSide(color: Brand.gold),
                  ),
                  onPressed: () {
                    setState(() => _error = null);
                    _start();
                  },
                  child: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
