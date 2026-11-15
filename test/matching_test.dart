import 'package:flutter_test/flutter_test.dart';
import 'package:powwot/src/matching.dart';

void main() {
  group('classifySubject', () {
    test('exact subjects', () {
      expect(classifySubject('MySpool POWER OFF Alert'), AlertKind.powerOff);
      expect(classifySubject('MySpool POWER ON Alert'), AlertKind.powerOn);
    });
    test('case-insensitive and whitespace tolerant', () {
      expect(classifySubject('myspool power off alert'), AlertKind.powerOff);
      expect(classifySubject('  MySpool   POWER\tON  Alert '), AlertKind.powerOn);
    });
    test('contains match (prefixes/suffixes)', () {
      expect(classifySubject('Fwd: MySpool POWER OFF Alert - Garage'), AlertKind.powerOff);
      expect(classifySubject('[dev42] MySpool POWER ON Alert'), AlertKind.powerOn);
    });
    test('ON is not mistaken for OFF and vice versa', () {
      expect(classifySubject('MySpool POWER ONLINE'), AlertKind.other);
      expect(classifySubject('MySpool POWER OFFLINE Alert'), AlertKind.other);
    });
    test('non-matching and null', () {
      expect(classifySubject(null), AlertKind.other);
      expect(classifySubject(''), AlertKind.other);
      expect(classifySubject('Welcome to your new mailbox'), AlertKind.other);
      expect(classifySubject('POWER OFF Alert'), AlertKind.other);
    });
  });
}
