/// The editor's *semantic* front-matter fields — the single source of truth.
///
/// Content lives here (as plain values); how it's laid out is decided by the
/// active [FormatSpec]. That separation is what makes an APA→MLA restyle
/// lossless: the same fields are simply re-projected, and anything a style has
/// no home for is parked, never dropped.
enum DocFieldKind {
  studentName,
  institutionName,
  courseName,
  instructorName,
  date;

  /// Placeholder shown when the field is empty.
  String get placeholder => switch (this) {
        DocFieldKind.studentName => 'Student Name',
        DocFieldKind.institutionName => 'Institution Name',
        DocFieldKind.courseName => 'Course Name',
        DocFieldKind.instructorName => 'Instructor Name',
        DocFieldKind.date => 'September 9, 2026',
      };

  /// Human label for the role (surfaced when the caret is inside it).
  String get label => switch (this) {
        DocFieldKind.studentName => 'Student name',
        DocFieldKind.institutionName => 'Institution name',
        DocFieldKind.courseName => 'Course name',
        DocFieldKind.instructorName => 'Instructor name',
        DocFieldKind.date => 'Date',
      };
}
