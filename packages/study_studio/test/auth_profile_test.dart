import 'package:flutter_test/flutter_test.dart';
import 'package:study_studio/study_studio.dart';

void main() {
  test('initials come from the name, else the email', () {
    expect(const AuthProfile(name: 'Hein Thant').initials, 'HT');
    expect(const AuthProfile(name: 'hein').initials, 'H');
    expect(const AuthProfile(email: 'dev.trhein@gmail.com').initials, 'DT');
    expect(const AuthProfile().initials, '?');
  });
}
