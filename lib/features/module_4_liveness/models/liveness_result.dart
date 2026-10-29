class LivenessResult {
  final String imagePath;
  final FaceBounds faceBounds;
  final double openEyesProbability;
  final double blinkEyesProbability;
  final double smileProbability;

  const LivenessResult({
    required this.imagePath,
    required this.faceBounds,
    required this.openEyesProbability,
    required this.blinkEyesProbability,
    required this.smileProbability,
  });
}

/// ML Kit face coordinates from the final capture. Keeping this primitive model
/// avoids coupling the embedding layer to Flutter's UI geometry classes.
class FaceBounds {
  final double left;
  final double top;
  final double width;
  final double height;

  const FaceBounds({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
