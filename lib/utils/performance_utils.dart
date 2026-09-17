import 'dart:collection';

class PerformanceTracker {
  final int windowSize;
  final Queue<double> _latencies = Queue<double>();
  final Queue<int> _timestamps = Queue<int>();
  double _sumLatency = 0.0;

  PerformanceTracker({this.windowSize = 20});

  void recordFrame(double latencyMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _latencies.add(latencyMs);
    _timestamps.add(now);
    _sumLatency += latencyMs;

    while (_latencies.length > windowSize) {
      _sumLatency -= _latencies.removeFirst();
    }
    while (_timestamps.length > windowSize) {
      _timestamps.removeFirst();
    }
  }

  double get averageLatencyMs {
    if (_latencies.isEmpty) return 0.0;
    return _sumLatency / _latencies.length;
  }

  double get currentFps {
    if (_timestamps.length < 2) return 0.0;
    final durationMs = _timestamps.last - _timestamps.first;
    if (durationMs <= 0) return 0.0;
    return ((_timestamps.length - 1) * 1000.0) / durationMs;
  }

  void reset() {
    _latencies.clear();
    _timestamps.clear();
    _sumLatency = 0.0;
  }
}
