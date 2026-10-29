/// Contract for the MobileFaceNet model supplied with this repository.
class FaceEmbeddingModel {
  static const assetPath = 'assets/mobile_face_net.tflite';
  static const inputWidth = 112;
  static const inputHeight = 112;
  static const inputChannels = 3;
  static const embeddingDimensions = 192;
}
