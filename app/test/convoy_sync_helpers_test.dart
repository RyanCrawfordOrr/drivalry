import 'package:drivalry/data/repos/convoy_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vote events refetch only for stops of this convoy', () {
    const known = {'s1', 's2'};
    expect(
      voteEventIsOurs({'stop_id': 's1', 'vote': 1}, const {}, known),
      isTrue,
    );
    expect(
      voteEventIsOurs(const {}, {'stop_id': 's2'}, known),
      isTrue,
      reason: 'a delete carries only the old row',
    );
    expect(voteEventIsOurs({'stop_id': 'other'}, const {}, known), isFalse);
    expect(voteEventIsOurs(const {}, const {}, known), isFalse);
    expect(voteEventIsOurs({'stop_id': 7}, const {}, known), isFalse);
  });
}
