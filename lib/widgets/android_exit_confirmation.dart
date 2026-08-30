import 'package:flutter/material.dart';

class AndroidExitConfirmation extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final VoidCallback onExit;
  final Duration confirmationWindow;

  const AndroidExitConfirmation({
    super.key,
    required this.child,
    required this.enabled,
    required this.onExit,
    this.confirmationWindow = const Duration(seconds: 2),
  });

  @override
  State<AndroidExitConfirmation> createState() =>
      _AndroidExitConfirmationState();
}

class _AndroidExitConfirmationState extends State<AndroidExitConfirmation> {
  DateTime? _lastBackPress;

  void _handlePop(bool didPop, Object? result) {
    if (didPop || !widget.enabled) return;

    final now = DateTime.now();
    final wasRecentlyPressed =
        _lastBackPress != null &&
        now.difference(_lastBackPress!) <= widget.confirmationWindow;
    if (wasRecentlyPressed) {
      widget.onExit();
      return;
    }

    _lastBackPress = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Press back again to exit')));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !widget.enabled,
      onPopInvokedWithResult: _handlePop,
      child: widget.child,
    );
  }
}
