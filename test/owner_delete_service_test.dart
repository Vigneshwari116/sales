import 'package:flutter_test/flutter_test.dart';
import 'package:sales/services/owner_delete_service.dart';

void main() {
  tearDown(() {
    OwnerDeleteService.instance.disable();
  });

  test('starts disabled and enables owner delete mode', () {
    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);

    OwnerDeleteService.instance.enable();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isTrue);
  });

  test('disable resets owner delete mode', () {
    OwnerDeleteService.instance.enable();
    OwnerDeleteService.instance.disable();

    expect(OwnerDeleteService.instance.isDeleteEnabled, isFalse);
  });
}
