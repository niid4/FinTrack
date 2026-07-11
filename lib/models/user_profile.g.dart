// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 0;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile()
      ..hasCompletedOnboarding = fields[0] as bool
      ..authMethod = fields[1] as String?
      ..mockUserId = fields[2] as String?
      ..userType = fields[3] as String?
      ..spendRange = fields[4] as String?
      ..overallMonthlyBudget = fields[5] as double
      ..permissionsRequested = fields[6] as bool
      ..monthlyIncome = fields[7] as double
      ..financialGoal = fields[8] as String?
      ..savingsTarget = fields[9] as double
      ..timelineMonths = fields[10] as int;
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.hasCompletedOnboarding)
      ..writeByte(1)
      ..write(obj.authMethod)
      ..writeByte(2)
      ..write(obj.mockUserId)
      ..writeByte(3)
      ..write(obj.userType)
      ..writeByte(4)
      ..write(obj.spendRange)
      ..writeByte(5)
      ..write(obj.overallMonthlyBudget)
      ..writeByte(6)
      ..write(obj.permissionsRequested)
      ..writeByte(7)
      ..write(obj.monthlyIncome)
      ..writeByte(8)
      ..write(obj.financialGoal)
      ..writeByte(9)
      ..write(obj.savingsTarget)
      ..writeByte(10)
      ..write(obj.timelineMonths);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
