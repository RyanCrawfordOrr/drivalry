import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:drivalry_packs/drivalry_packs.dart';
import 'package:drivalry_scoring/drivalry_scoring.dart' show RoadClass;
import 'package:test/test.dart';

void main() {
  group('varint', () {
    test('LEB128 vectors', () {
      Uint8List enc(int v) => (ByteWriter()..writeVarint(v)).takeBytes();
      expect(enc(0), [0x00]);
      expect(enc(1), [0x01]);
      expect(enc(127), [0x7f]);
      expect(enc(128), [0x80, 0x01]);
      expect(enc(300), [0xac, 0x02]);
      expect(enc(16384), [0x80, 0x80, 0x01]);
      expect(enc(77800000), [0xc0, 0xc4, 0x8c, 0x25]);
      for (final v in [0, 1, 127, 128, 300, 1 << 35, 0x7fffffffffffffff]) {
        expect(ByteReader(enc(v)).readVarint(), v);
      }
    });

    test('zigzag vectors', () {
      expect(zigzagEncode(0), 0);
      expect(zigzagEncode(-1), 1);
      expect(zigzagEncode(1), 2);
      expect(zigzagEncode(-2), 3);
      expect(zigzagEncode(100), 200);
      expect(zigzagEncode(-200), 399);
      expect(zigzagEncode(38900000), 77800000);
      expect(zigzagEncode(-77000000), 153999999);
      for (final v in [0, 1, -1, 100, -200, 38900000, -77000000, 1 << 40]) {
        expect(zigzagDecode(zigzagEncode(v)), v);
      }
    });

    test('reader fails cleanly on truncation', () {
      final r = ByteReader(Uint8List.fromList([0x80]));
      expect(r.readVarint, throwsFormatException);
    });
  });

  group('TileCodec', () {
    PackWay way({
      int id = 1,
      String? name,
      int? max,
      int? maxb,
      bool mph = false,
      int oneway = 0,
      bool roundabout = false,
      LimitSource source = LimitSource.none,
      RoadClass cls = RoadClass.residential,
    }) => PackWay(
      id: id,
      roadClass: cls,
      name: name,
      maxForward: max,
      maxBackward: maxb,
      mph: mph,
      oneway: oneway,
      roundabout: roundabout,
      source: source,
      lats: [38.9, 38.9001, 38.90025],
      lons: [-77.0, -77.0002, -77.00031],
    );

    final names = ['Elm Street', 'Main Street'];
    int nameIdOf(String n) => names.indexOf(n) + 1;
    String? nameOf(int id) =>
        id >= 1 && id <= names.length ? names[id - 1] : null;

    test('round trips every field', () {
      final ways = [
        way(
          id: 7,
          name: 'Main Street',
          max: 35,
          mph: true,
          source: LimitSource.tag,
          cls: RoadClass.primary,
        ),
        way(
          id: 3,
          max: 50,
          maxb: 30,
          source: LimitSource.tag,
          oneway: 0,
          cls: RoadClass.secondary,
        ),
        way(id: 9, maxb: 25, mph: true, source: LimitSource.tag, oneway: 2),
        way(
          id: 12,
          name: 'Elm Street',
          oneway: 1,
          roundabout: true,
          cls: RoadClass.motorway,
        ),
        way(
          id: 4,
          max: 30,
          source: LimitSource.implied,
          cls: RoadClass.unknown,
        ),
        way(id: 1 << 33, cls: RoadClass.service), // large ids are varints
      ];
      final blob = TileCodec.encode(ways, nameIdOf);
      final decoded = TileCodec.decode(blob, nameOf);
      expect(decoded.map((w) => w.id), [3, 4, 7, 9, 12, 1 << 33]); // sorted
      final byId = {for (final w in decoded) w.id: w};

      final main = byId[7]!;
      expect(main.name, 'Main Street');
      expect(main.maxForward, 35);
      expect(main.maxBackward, isNull);
      expect(main.mph, isTrue);
      expect(main.source, LimitSource.tag);
      expect(main.roadClass, RoadClass.primary);
      expect(main.confidence, 0.9);

      final two = byId[3]!;
      expect(two.maxForward, 50);
      expect(two.maxBackward, 30);
      expect(two.mph, isFalse);
      expect(two.oneway, 0);

      final backOnly = byId[9]!;
      expect(backOnly.maxForward, isNull);
      expect(backOnly.maxBackward, 25);
      expect(backOnly.oneway, 2);
      expect(backOnly.name, isNull);

      final rb = byId[12]!;
      expect(rb.name, 'Elm Street');
      expect(rb.oneway, 1);
      expect(rb.roundabout, isTrue);
      expect(rb.source, LimitSource.none);
      expect(rb.confidence, 0);
      expect(rb.roadClass, RoadClass.motorway);

      expect(byId[4]!.source, LimitSource.implied);
      expect(byId[4]!.confidence, 0.5);
      expect(byId[4]!.roadClass, RoadClass.unknown);
      expect(byId[1 << 33]!.roadClass, RoadClass.service);

      for (final w in decoded) {
        expect(w.pointCount, 3);
        expect(w.lats[0], closeTo(38.9, 1e-9));
        expect(w.lons[1], closeTo(-77.0002, 1e-9));
        expect(w.lats[2], closeTo(38.90025, 1e-9));
        expect(w.lons[2], closeTo(-77.00031, 1e-9));
      }
    });

    test('hand-built blob from the format document decodes', () {
      // One way: id 5, residential (5), name_id 1, 25 mph forward only,
      // two-way, src=tag, mph; two points (38.9, -77.0) then +100e-6, -200e-6.
      final raw = Uint8List.fromList([
        0x01, // blob_version
        0x01, // way_count
        0x05, // way_id
        0x05, // cls residential
        0x02, // name_id_plus_one = 1 + 1
        0x1a, // max_plus_one = 25 + 1
        0x00, // maxb_plus_one = same as forward
        0x14, // flags: oneway 0, src 1 (<<2 = 4), mph 0x10
        0x02, // point_count
        0xc0, 0xc4, 0x8c, 0x25, // zigzag(38900000)
        0xff, 0xb4, 0xb7, 0x49, // zigzag(-77000000)
        0xc8, 0x01, // zigzag(100)
        0x8f, 0x03, // zigzag(-200)
      ]);
      final fromRaw = TileCodec.decodeRaw(raw, nameOf);
      final compressed = Uint8List.fromList(ZLibEncoder(level: 9).convert(raw));
      final fromBlob = TileCodec.decode(compressed, nameOf);
      for (final ways in [fromRaw, fromBlob]) {
        expect(ways, hasLength(1));
        final w = ways.single;
        expect(w.id, 5);
        expect(w.roadClass, RoadClass.residential);
        expect(w.name, 'Elm Street');
        expect(w.maxForward, 25);
        expect(w.maxBackward, isNull);
        expect(w.mph, isTrue);
        expect(w.oneway, 0);
        expect(w.roundabout, isFalse);
        expect(w.source, LimitSource.tag);
        expect(w.lats, [38.9, 38.9001]);
        expect(w.lons, [-77.0, -77.0002]);
        expect(w.limitMps(forward: true), closeTo(11.176, 1e-9));
      }
      // And our encoder produces exactly these bytes.
      expect(TileCodec.encodeRaw(fromRaw, nameIdOf), raw);
    });

    test('rejects unknown blob versions and trailing bytes', () {
      expect(
        () => TileCodec.decodeRaw(Uint8List.fromList([0x02, 0x00]), nameOf),
        throwsFormatException,
      );
      expect(
        () =>
            TileCodec.decodeRaw(Uint8List.fromList([0x01, 0x00, 0x00]), nameOf),
        throwsFormatException,
      );
    });
  });

  group('PackWay limits', () {
    PackWay w({int? max, int? maxb, bool mph = true, int oneway = 0}) =>
        PackWay(
          id: 1,
          roadClass: RoadClass.primary,
          maxForward: max,
          maxBackward: maxb,
          mph: mph,
          oneway: oneway,
          source: LimitSource.tag,
          lats: const [0, 0.001],
          lons: const [0, 0.001],
        );

    test('35 mph is 15.6464 m/s', () {
      expect(w(max: 35).limitMps(forward: true), closeTo(15.6464, 1e-9));
      expect(w(max: 35).postedLimit(forward: true), 35);
      expect(w(max: 35).unitLabel, 'mph');
    });

    test('50 km/h is 13.888 m/s', () {
      expect(
        w(max: 50, mph: false).limitMps(forward: true),
        closeTo(13.8888888889, 1e-9),
      );
      expect(w(max: 50, mph: false).unitLabel, 'km/h');
    });

    test('backward uses maxBackward when set, otherwise forward', () {
      expect(
        w(max: 45, maxb: 35).limitMps(forward: false),
        closeTo(35 * 0.44704, 1e-9),
      );
      expect(
        w(max: 45, maxb: 35).limitMps(forward: true),
        closeTo(45 * 0.44704, 1e-9),
      );
      expect(w(max: 45).limitMps(forward: false), closeTo(45 * 0.44704, 1e-9));
      expect(w(maxb: 25).limitMps(forward: true), isNull);
      expect(w(maxb: 25).limitMps(forward: false), closeTo(25 * 0.44704, 1e-9));
      expect(w().limitMps(forward: true), isNull);
    });

    test('allows() follows oneway', () {
      expect(w(oneway: 0).allows(forward: false), isTrue);
      expect(w(oneway: 1).allows(forward: true), isTrue);
      expect(w(oneway: 1).allows(forward: false), isFalse);
      expect(w(oneway: 2).allows(forward: true), isFalse);
      expect(w(oneway: 2).allows(forward: false), isTrue);
    });
  });
}
