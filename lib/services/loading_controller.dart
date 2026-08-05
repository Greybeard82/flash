import 'package:flutter/foundation.dart';

/// Global, reference-counted busy flag. One instance, app-wide.
class LoadingController extends ChangeNotifier {
  static final LoadingController instance = LoadingController._();

  LoadingController._();

  int _activeCount = 0;
  final List<String?> _labels = [];

  bool get isBusy => _activeCount > 0;
  int get activeCount => _activeCount;
  String? get label => _labels.isEmpty ? null : _labels.last;

  void begin([String? label]) {
    _activeCount++;
    _labels.add(label);
    notifyListeners();
  }

  void end() {
    if (_activeCount == 0) return;
    _activeCount--;
    if (_labels.isNotEmpty) _labels.removeLast();
    notifyListeners();
  }

  Future<T> run<T>(Future<T> Function() action, {String? label}) async {
    begin(label);
    try {
      return await action();
    } finally {
      end();
    }
  }

  void reset() {
    _activeCount = 0;
    _labels.clear();
    notifyListeners();
  }
}
