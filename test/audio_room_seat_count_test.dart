import 'package:flutter_test/flutter_test.dart';
import 'package:belive/models/audio_room_root.dart';

Map<String, dynamic> seat(int position, {String? userId, String? frame}) => {
  'position': position,
  'userId': userId,
  'name': userId != null ? 'u$position' : null,
  'image': userId != null ? 'img' : null,
  'reserved': userId != null,
  'avatarFrameImage': frame,
  'mute': 0,
  'lock': false,
};

void main() {
  group('AudioRoomUser seatCount semantics', () {
    test(
      '9 people (seatCount=9) with 8-seat grid stays 9 — no phantom seat',
      () {
        final room = AudioRoomUser.fromJson({
          '_id': 'room1',
          'seatCount': 9,
          'seat': List.generate(8, (i) => seat(i)),
        });
        expect(room.seatCount, 9);
      },
    );

    test('polluted doc seatCount=9 + 9-seat array still yields 9 people', () {
      // Old clients could persist a 9th grid seat; the stored count (9
      // people) is authoritative — grid renders 8, extra entry is dropped.
      final room = AudioRoomUser.fromJson({
        '_id': 'room2',
        'seatCount': 9,
        'seat': List.generate(9, (i) => seat(i)),
      });
      expect(room.seatCount, 9);
    });

    test('legacy grid count (8) derives people count from seat array', () {
      final room = AudioRoomUser.fromJson({
        '_id': 'room3',
        'seatCount': 8,
        'seat': List.generate(8, (i) => seat(i)),
      });
      expect(room.seatCount, 9); // 8 grid + host
    });

    test('missing seatCount derives from array (12 grid -> 13 people)', () {
      final room = AudioRoomUser.fromJson({
        '_id': 'room4',
        'seat': List.generate(12, (i) => seat(i)),
      });
      expect(room.seatCount, 13);
    });
  });

  group('SeatItem frame ownership', () {
    test('seat without frame parses null avatarFrame', () {
      final s = SeatItem.fromJson(seat(0, userId: 'u1'));
      expect(s.avatarFrame, isNull);
    });

    test('seat parses its own frame only', () {
      final s = SeatItem.fromJson(
        seat(1, userId: 'u2', frame: 'frame_u2.svga'),
      );
      expect(s.avatarFrame, 'frame_u2.svga');
    });

    test(
      'copyWith preserves frame — caller must build fresh SeatItem on occupant change',
      () {
        final old = SeatItem.fromJson(
          seat(1, userId: 'host', frame: 'host.svga'),
        );
        final leaked = old.copyWith(userId: 'guest');
        expect(leaked.avatarFrame, 'host.svga'); // documents the leak vector
        final fresh = SeatItem(position: 1, userId: 'guest');
        expect(fresh.avatarFrame, isNull); // the fix pattern
      },
    );
  });
}
