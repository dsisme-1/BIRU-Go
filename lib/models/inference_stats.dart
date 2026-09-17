class InferenceStats {
  final double inferenceLatencyMs;
  final double preprocessLatencyMs;
  final double postprocessLatencyMs;

  double get totalLatencyMs =>
      preprocessLatencyMs + inferenceLatencyMs + postprocessLatencyMs;

  double get fps => totalLatencyMs > 0 ? 1000.0 / totalLatencyMs : 0.0;

  final String inputShape;
  final String outputShape;
  final int detectionCount;

  const InferenceStats({
    this.inferenceLatencyMs = 0.0,
    this.preprocessLatencyMs = 0.0,
    this.postprocessLatencyMs = 0.0,
    this.inputShape = '[1, 3, 640, 640]',
    this.outputShape = '[1, 559, 8400]',
    this.detectionCount = 0,
  });

  InferenceStats copyWith({
    double? inferenceLatencyMs,
    double? preprocessLatencyMs,
    double? postprocessLatencyMs,
    String? inputShape,
    String? outputShape,
    int? detectionCount,
  }) {
    return InferenceStats(
      inferenceLatencyMs: inferenceLatencyMs ?? this.inferenceLatencyMs,
      preprocessLatencyMs: preprocessLatencyMs ?? this.preprocessLatencyMs,
      postprocessLatencyMs: postprocessLatencyMs ?? this.postprocessLatencyMs,
      inputShape: inputShape ?? this.inputShape,
      outputShape: outputShape ?? this.outputShape,
      detectionCount: detectionCount ?? this.detectionCount,
    );
  }
}
