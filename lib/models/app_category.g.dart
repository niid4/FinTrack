// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_category.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AppCategoryAdapter extends TypeAdapter<AppCategory> {
  @override
  final int typeId = 1;

  @override
  AppCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AppCategory()
      ..name = fields[0] as String
      ..iconName = fields[1] as String?
      ..isSystem = fields[2] as bool
      ..isSelected = fields[3] as bool
      ..monthlyAllocation = fields[4] as double;
  }

  @override
  void write(BinaryWriter writer, AppCategory obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.iconName)
      ..writeByte(2)
      ..write(obj.isSystem)
      ..writeByte(3)
      ..write(obj.isSelected)
      ..writeByte(4)
      ..write(obj.monthlyAllocation);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
