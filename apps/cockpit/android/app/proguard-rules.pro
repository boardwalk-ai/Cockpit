# ML Kit brings WorkManager 2.7 with Room 2.2, whose keep rule predates R8
# full mode: it keeps the generated database class but not its constructor,
# and WorkManager crashes at app start creating WorkDatabase.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
