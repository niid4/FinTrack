// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_transaction.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppTransactionAdapter extends TypeAdapter<AppTransaction> {
  @override
  final int typeId = 2;

  @override
  AppTransaction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppTransaction()
      ..amount = fields[0] as double
      ..merchant = fields[1] as String
      ..date = fields[2] as DateTime
      ..categoryId = fields[3] as int?
      ..customCategory = fields[4] as String?
      ..isUncategorized = fields[5] as bool
      // Field 6 was added later; older records won't have it.
      ..isSkipped = fields[6] as bool? ?? false;
  }

  @override
  void write(BinaryWriter writer, AppTransaction obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.amount)
      ..writeByte(1)
      ..write(obj.merchant)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.categoryId)
      ..writeByte(4)
      ..write(obj.customCategory)
      ..writeByte(5)
      ..write(obj.isUncategorized)
      ..writeByte(6)
      ..write(obj.isSkipped);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppTransactionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
