# Study Studio Test Suite

This folder contains the automated tests for the Study Studio Flutter package.

The suite covers:

- Widget tests for the main Study Studio screens
- Loading, empty, error, and data states
- Golden tests for visually rich screens
- Unit tests for mastery logic, weak-topic selection, and DTO mapping

## Test structure

```text
test/
├── data/
│   └── api_repository_test.dart
├── golden/
│   ├── flashcards_page_golden_test.dart
│   ├── progress_page_golden_test.dart
│   ├── quiz_me_page_golden_test.dart
│   └── goldens/
├── helpers/
│   ├── fake_studio_repository.dart
│   └── test_app.dart
├── presentation/
│   ├── dashboard_page_test.dart
│   ├── flashcards_page_test.dart
│   ├── home_page_test.dart
│   ├── progress_page_test.dart
│   ├── quiz_me_page_test.dart
│   ├── teach_me_page_test.dart
│   ├── screens_14_15_test.dart
│   └── screens_16_17_test.dart
└── unit/
    ├── dto_mappers_test.dart
    ├── studio_mastery_test.dart
    └── topic_mastery_test.dart