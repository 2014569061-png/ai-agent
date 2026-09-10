import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_agent/infrastructure/tools/schema_validator.dart';

void main() {
  const validator = JsonSchemaSubsetValidator();

  test('validates required, type, enum, pattern and maxLength', () {
    const schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'mode': {
          'type': 'string',
          'enum': ['fast', 'safe']
        },
        'name': {'type': 'string', 'pattern': r'^[a-z]+$', 'maxLength': 8},
      },
      'required': ['mode', 'name'],
      'additionalProperties': false,
    };
    expect(
        validator.validate({'mode': 'safe', 'name': 'nexus'}, schema).isValid,
        isTrue);
    expect(
        validator.validate({'mode': 'unsafe', 'name': 'nexus'}, schema).isValid,
        isFalse);
    expect(validator.validate({'mode': 'safe'}, schema).isValid, isFalse);
    expect(
        validator.validate({'mode': 'safe', 'name': 'NEXUS'}, schema).isValid,
        isFalse);
  });

  test('validates nested items and local refs', () {
    const schema = <String, dynamic>{
      r'$defs': {
        'step': {
          'type': 'object',
          'properties': {
            'id': {'type': 'string'}
          },
          'required': ['id'],
        },
      },
      'type': 'array',
      'items': {r'$ref': r'#/$defs/step'},
    };
    expect(
        validator.validate([
          {'id': 's1'}
        ], schema).isValid,
        isTrue);
    expect(
        validator.validate([
          {'name': 'missing'}
        ], schema).isValid,
        isFalse);
  });
}
