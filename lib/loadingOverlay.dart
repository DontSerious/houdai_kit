library houdai_kit;

import 'package:flutter/material.dart';

class LoadingOverlay {
  static final LoadingOverlay _singleton = LoadingOverlay._internal();
  factory LoadingOverlay() {
    return _singleton;
  }
  LoadingOverlay._internal();

  OverlayEntry? _overlayEntry;
  BuildContext? _savedContext;

  void setContext(BuildContext context) {
    _savedContext = context;
  }

  void show(Widget indicator) {
    if (_overlayEntry != null || _savedContext == null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0.0,
        left: 0.0,
        right: 0.0,
        bottom: 0.0,
        child: Material(
          color: Colors.black54,
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(20.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10.0),
              ),
              child: indicator,
            ),
          ),
        ),
      ),
    );

    Overlay.of(_savedContext!).insert(_overlayEntry!);
  }

  void showLoading(ValueNotifier<double> progressNotifier, String text) {
    show(
      ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (context, progress, child) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Flexible(
                child: Text(
                  '$text: ${(progress * 100).toInt()}%',
                  style: const TextStyle(fontSize: 20.0, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 20.0),
              SizedBox(
                width: 50.0,
                height: 50.0,
                child: CircularProgressIndicator(
                  strokeWidth: 5.0,
                  value: progress,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}