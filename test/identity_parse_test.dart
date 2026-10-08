import 'package:flutter_test/flutter_test.dart';
import 'package:belive/models/audio_room_root.dart';
import 'package:belive/models/json_annotation_helper.dart';
import 'package:belive/widgets/live_moderation_sheet.dart';

Map<String, dynamic> levelDoc([int n = 12]) => {
  '_id': '683264854b4e392c80edb59b',
  'name': 'Level $n',
  'image': 'https://cdn.unilive.me/level/lv$n.png',
  'coin': 25000000,
  'accessibleFunction': 'abc',
};

void main() {
  group('isLevelLikeMap', () {
    test('flags a populated level doc', () {
      expect(isLevelLikeMap(levelDoc()), isTrue);
    });
    test('flags a bare level doc (no coin/bgColor)', () {
      expect(
        isLevelLikeMap({
          '_id': '683264854b4e392c80edb59b',
          'name': 'Level 32',
          'image': 'https://cdn.unilive.me/badge/x.png',
        }),
        isTrue,
      );
    });
    test('does not flag a real user map named like a person', () {
      expect(
        isLevelLikeMap({'userId': 'u1', 'name': 'Murshad', 'image': 'x.jpg'}),
        isFalse,
      );
    });
    test('does not flag a user doc whose name literally is Level 12', () {
      // A real user record would carry userId/username etc.
      expect(
        isLevelLikeMap({
          '_id': '69f9a81dd9973f8b014008f2',
          'userId': '69f9a81dd9973f8b014008f2',
          'name': 'Level 12',
        }),
        isFalse,
      );
    });
  });

  group('parseUserId', () {
    test('prefers nested userId over a conflicting id', () {
      // Logged prod shape: user.id = host, user.userId = commenter.
      final m = {
        'id': '6a0e4186b27dcdf7985903b5',
        'userId': '69f9a81dd9973f8b014008f2',
        'name': 'Murshad',
      };
      expect(parseUserId(m), '69f9a81dd9973f8b014008f2');
    });
    test('returns null for a level doc', () {
      expect(parseUserId(levelDoc()), isNull);
    });
    test('string passes through', () {
      expect(
        parseUserId('69f9a81dd9973f8b014008f2'),
        '69f9a81dd9973f8b014008f2',
      );
    });
  });

  group('ViewerEntry.fromJson', () {
    test('a level doc map is not a viewer', () {
      final v = ViewerEntry.fromJson(levelDoc(32));
      expect(v.userId, isNull);
    });

    test('bare level doc (no coin) is not a viewer', () {
      final v = ViewerEntry.fromJson({
        '_id': '683264854b4e392c80edb59b',
        'name': 'Level 12',
        'image': 'https://cdn.unilive.me/level/lv12.png',
      });
      expect(v.userId, isNull);
    });

    test('vipDetails map is not a viewer', () {
      final v = ViewerEntry.fromJson({
        'tierId': 'vip6',
        'name': 'Vip 6',
        'vipTagUrl': 'x.png',
      });
      expect(v.userId, isNull);
    });

    test('real viewer with nested level keeps real identity', () {
      final v = ViewerEntry.fromJson({
        'userId': '69f9a81dd9973f8b014008f2',
        'name': 'Murshad',
        'image': 'u.jpg',
        'level': levelDoc(),
        'vipDetails': {'tierId': 'vip1', 'vipTagUrl': 't.png'},
      });
      expect(v.userId, '69f9a81dd9973f8b014008f2');
      expect(v.name, 'Murshad');
    });

    test('nested user map resolves userId over conflicting id', () {
      final v = ViewerEntry.fromJson({
        'name': 'x',
        'user': {
          'id': '6a0e4186b27dcdf7985903b5',
          'userId': '69f9a81dd9973f8b014008f2',
          'name': 'Murshad',
        },
      });
      expect(v.userId, '69f9a81dd9973f8b014008f2');
    });

    test('level doc smuggled in the user slot yields no identity', () {
      final v = ViewerEntry.fromJson({'user': levelDoc()});
      expect(v.userId, isNull);
    });
  });

  group('SeatItem.fromJson', () {
    test('logged comment-payload shape resolves the real user', () {
      final s = SeatItem.fromJson({
        'userId': '69f9a81dd9973f8b014008f2',
        'name': 'Murshad',
        'image': 'https://cdn.unilive.me/user/x.jpg',
        'level': levelDoc(),
        'user': {
          'id': '6a0e4186b27dcdf7985903b5',
          'userId': '69f9a81dd9973f8b014008f2',
          'name': 'Murshad',
          'image': 'https://cdn.unilive.me/user/x.jpg',
        },
      });
      expect(s.userId, '69f9a81dd9973f8b014008f2');
      expect(s.name, 'Murshad');
    });

    test('level doc in the userId slot yields no identity', () {
      final s = SeatItem.fromJson({
        'position': 0,
        'userId': levelDoc(),
        'reserved': true,
      });
      expect(s.userId, isNull);
    });

    test('level doc in the user slot yields no identity', () {
      final s = SeatItem.fromJson({
        'position': 0,
        'user': levelDoc(),
        'reserved': true,
      });
      expect(s.userId, isNull);
    });

    test('normal seat keeps its identity', () {
      final s = SeatItem.fromJson({
        'position': 0,
        'userId': '69f9a81dd9973f8b014008f2',
        'name': 'Murshad',
        'image': 'u.jpg',
      });
      expect(s.userId, '69f9a81dd9973f8b014008f2');
      expect(s.name, 'Murshad');
    });
  });
}
