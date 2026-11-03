import 'scene.dart';

/// Every store screenshot, in store order. Each entry is a factory because a
/// scene is built and disposed once per output size.
final List<ArtScene Function()> sceneFactories = [];
