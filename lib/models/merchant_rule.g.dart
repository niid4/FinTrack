// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'merchant_rule.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MerchantRuleAdapter extends TypeAdapter<MerchantRule> {
  @override
  final int typeId = 4;

  @override
  MerchantRule read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return MerchantRule()
      ..merchantName = fields[0] as String
      ..category = fields[1] as String
      ..resolvedBy = fields[2] as String;
  }

  @override
  void write(BinaryWriter writer, MerchantRule obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.merchantName)
      ..writeByte(1)
      ..write(obj.category)
      ..writeByte(2)
      ..write(obj.resolvedBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MerchantRuleAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
