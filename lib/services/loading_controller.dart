import 'package:flutter/foundation.dart';

/// Global, reference-counted busy flag. One instance, app-wide.
class LoadingController extends ChangeNotifier {
  static final LoadingController instance = LoadingController._();

  LoadingController._();

  int _activeCount = 0;

  /// Labels keyed by the token [begin] handed out, so [end] retires the label
  /// belonging to *its own* operation. Popping the last label instead — as
  /// this did before — showed the wrong caption whenever two operations
  /// overlapped and the shorter one finished first.
  final Map<int, String?> _labels = {};
  int _nextToken = 0;

  bool get isBusy => _activeCount > 0;
  int get activeCount => _activeCount;

  /// The most recently started operation that is still running.
  String? get label => _labels.isEmpty ? null : _labels[_labels.keys.last];

  /// Returns a token that must be handed back to [end].
  int begin([String? label]) {
    _activeCount++;
    final token = _nextToken++;
    _labels[token] = label;
    notifyListeners();
    return token;
  }

  void end(int token) {
    if (_activeCount == 0) return;
    _activeCount--;
    _labels.remove(token);
    notifyListeners();
  }

  Future<T> run<T>(Future<T> Function() action, {String? label}) async {
    final token = begin(label);
    try {
      return await action();
    } finally {
      end(token);
    }
  }

  void reset() {
    _activeCount = 0;
    _labels.clear();
    notifyListeners();
  }
}
