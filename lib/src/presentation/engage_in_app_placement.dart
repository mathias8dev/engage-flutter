import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/engage_runtime.dart';
import '../domain/models.dart';

/// Hosts the official native Engage renderer for an embedded placement.
///
/// Flutter platform views need a layout constraint, so [height] defines the
/// slot height. The host collapses when no content is eligible, unless a
/// placeholder is supplied or the last content requested `reserveSpace`.
final class EngageInAppPlacement extends StatefulWidget {
  const EngageInAppPlacement({
    required this.placementKey,
    required this.height,
    this.placeholder,
    super.key,
  }) : assert(height >= 0 && height < double.infinity);

  final String placementKey;
  final double height;
  final Widget? placeholder;

  @override
  State<EngageInAppPlacement> createState() => _EngageInAppPlacementState();
}

final class _EngageInAppPlacementState extends State<EngageInAppPlacement> {
  StreamSubscription<InAppContent?>? _subscription;
  InAppContent? _content;
  bool _reserveSpace = false;

  @override
  void initState() {
    super.initState();
    _observe();
  }

  @override
  void didUpdateWidget(EngageInAppPlacement oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placementKey != widget.placementKey) {
      _subscription?.cancel();
      _content = null;
      _reserveSpace = false;
      _observe();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _observe() {
    _subscription = EngageRuntime.client.inApp
        .placement(widget.placementKey)
        .listen((content) {
          final presentation = content?.presentation;
          if (presentation is EmbeddedPresentation) {
            _reserveSpace =
                presentation.emptyState == EmptyStatePolicy.reserveSpace;
          }
          if (mounted) {
            setState(() => _content = content);
          } else {
            _content = content;
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    if (_content == null) {
      if (widget.placeholder case final placeholder?) {
        return SizedBox(height: widget.height, child: placeholder);
      }
      return _reserveSpace
          ? SizedBox(height: widget.height)
          : const SizedBox.shrink();
    }

    final params = <String, Object?>{'key': widget.placementKey};
    final view = switch (defaultTargetPlatform) {
      TargetPlatform.android => AndroidView(
        viewType: 'io.engage.flutter/in_app_placement',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      TargetPlatform.iOS => UiKitView(
        viewType: 'io.engage.flutter/in_app_placement',
        creationParams: params,
        creationParamsCodec: const StandardMessageCodec(),
      ),
      _ => widget.placeholder ?? const SizedBox.shrink(),
    };
    return SizedBox(height: widget.height, child: view);
  }
}
