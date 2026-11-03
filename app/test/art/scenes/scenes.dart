import 'badges_scene.dart';
import 'convoy_scene.dart';
import 'drive_scene.dart';
import 'friends_scene.dart';
import 'league_scene.dart';
import 'scene.dart';
import 'stops_scene.dart';
import 'trip_scene.dart';
import 'wrapped_scene.dart';

/// Every store screenshot, in store order. Each entry is a factory because a
/// scene is built and disposed once per output size.
final List<ArtScene Function()> sceneFactories = [
  DriveScene.new,
  TripScene.new,
  LeagueScene.new,
  FriendsScene.new,
  ConvoyRadioScene.new,
  () => WrappedScene(card: 2),
  BadgesScene.new,
  ConvoyStopsScene.new,
];
