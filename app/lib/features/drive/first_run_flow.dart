import 'package:flutter/material.dart';

import '../../app/ui/ui.dart';
import '../../tracking/tracking_models.dart';

/// First launch (docs/12 §7): three full-screen pages, one button each. What
/// Drivalry does, why location must be "all the time", then motion. The
/// tracking plugin asks the OS for everything in one call, so the location
/// page's "Allow" fires the prompts and the motion page confirms, retries or
/// sends the person to Settings.
class FirstRunFlow extends StatefulWidget {
  const FirstRunFlow({
    super.key,
    required this.permissions,
    required this.onRequest,
    required this.onOpenSettings,
    required this.onDone,
  });

  final TrackingPermissions permissions;

  /// Asks the OS; resolves to the permissions afterwards.
  final Future<TrackingPermissions> Function() onRequest;
  final VoidCallback onOpenSettings;

  /// Finished or skipped: the Drive tab takes over.
  final VoidCallback onDone;

  @override
  State<FirstRunFlow> createState() => _FirstRunFlowState();
}

class _FirstRunFlowState extends State<FirstRunFlow> {
  final _pages = PageController();
  int _page = 0;
  bool _busy = false;

  /// The motion page asked once already; the next tap opens Settings.
  bool _askedForMotion = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _next() {
    Haptics.tap();
    return _pages.nextPage(duration: Motion.screen, curve: Motion.standard);
  }

  Future<void> _allowLocation() async {
    setState(() => _busy = true);
    final perms = await widget.onRequest();
    if (!mounted) return;
    setState(() => _busy = false);
    if (perms.sufficientForAutoTracking) {
      Haptics.success();
      widget.onDone();
      return;
    }
    await _next();
  }

  Future<void> _allowMotion() async {
    if (widget.permissions.sufficientForAutoTracking ||
        widget.permissions.motion == SimplePermission.granted) {
      widget.onDone();
      return;
    }
    if (_askedForMotion) {
      widget.onOpenSettings();
      return;
    }
    setState(() {
      _busy = true;
      _askedForMotion = true;
    });
    final perms = await widget.onRequest();
    if (!mounted) return;
    setState(() => _busy = false);
    if (perms.sufficientForAutoTracking) {
      Haptics.success();
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final motionGranted =
        widget.permissions.motion == SimplePermission.granted ||
        widget.permissions.sufficientForAutoTracking;
    final String motionLabel;
    if (motionGranted) {
      motionLabel = 'Done';
    } else if (_askedForMotion) {
      motionLabel = 'Open settings';
    } else {
      motionLabel = 'Allow';
    }
    return Scaffold(
      body: SafeArea(
        child: PageView(
          key: const Key('first-run'),
          controller: _pages,
          onPageChanged: (i) => setState(() => _page = i),
          children: [
            _Page(
              index: 0,
              current: _page,
              icon: Icons.directions_car_outlined,
              kicker: 'Drivalry',
              headline: 'Every drive gets a score.',
              body:
                  'Drives start and stop on their own and are scored on this '
                  'phone when you park.',
              button: PrimaryButton(label: 'Next', onPressed: _next),
            ),
            _Page(
              index: 1,
              current: _page,
              icon: Icons.location_on_outlined,
              kicker: 'Location',
              headline: 'Allow location all the time.',
              body:
                  'Drives then start on their own, even when the app is '
                  'closed.',
              button: PrimaryButton(
                label: 'Allow',
                busy: _busy,
                onPressed: _allowLocation,
              ),
              secondary: TextButton(
                onPressed: widget.onDone,
                child: const Text('Not now'),
              ),
            ),
            _Page(
              index: 2,
              current: _page,
              icon: Icons.directions_run,
              kicker: 'Motion',
              headline: 'Allow motion.',
              body:
                  'Tells the phone you have started moving, so recording '
                  'begins on time.',
              status: motionGranted
                  ? const Pill(
                      'Allowed',
                      tone: PillTone.positive,
                      icon: Icons.check,
                    )
                  : null,
              button: PrimaryButton(
                label: motionLabel,
                busy: _busy,
                onPressed: _allowMotion,
              ),
              secondary: motionGranted
                  ? null
                  : TextButton(
                      onPressed: widget.onDone,
                      child: const Text('Not now'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.index,
    required this.current,
    required this.icon,
    required this.kicker,
    required this.headline,
    required this.body,
    required this.button,
    this.secondary,
    this.status,
  });

  final int index;
  final int current;
  final IconData icon;
  final String kicker;
  final String headline;
  final String body;
  final Widget button;
  final Widget? secondary;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Each element arrives a beat after the last (docs/12 §5b).
    final staged = <Widget>[
      Icon(icon, size: 48, color: scheme.primary),
      Kicker(kicker),
      Text(headline, style: context.headline),
      Text(body, style: context.bodyMuted),
      if (status != null) Align(alignment: Alignment.centerLeft, child: status),
    ];
    // The words start near the top of the page (docs/12 §2: no empty band
    // over 48 px); the dots and the button sit at the bottom.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.xl,
        Space.gutter,
        Space.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, w) in staged.indexed) ...[
            if (i > 0) SizedBox(height: i == 1 ? Space.xl : Space.md),
            Reveal(delay: Reveal.stagger(i), child: w),
          ],
          const Spacer(),
          Reveal(
            delay: Reveal.stagger(staged.length),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Dots(count: 3, current: current),
                const SizedBox(height: Space.xl),
                button,
                const SizedBox(height: Space.sm),
                SizedBox(
                  height: Sizes.touch,
                  child: secondary == null ? null : Center(child: secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: Space.sm),
          AnimatedContainer(
            duration: Motion.quick,
            width: i == current ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == current ? scheme.primary : scheme.outlineVariant,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ],
      ],
    );
  }
}
