/// Doc Oct — academic document workstation (Flutter rewrite).
///
/// Doc Oct's exact web screens, restyled into the shared **borderless**
/// (Swiss · GitBook) design system from `cockpit_ui` (`BorderlessTheme`, Plus
/// Jakarta Sans, the floating `ThemeSwitcher`). Phase 1: loading screen +
/// wizard (welcome → setup → analysis) + workspace; the editor is Phase 2.
library;

export 'src/application/providers.dart';
export 'src/application/sources.dart';
export 'src/domain/citation_templates.dart';
export 'src/domain/doc_dates.dart';
export 'src/domain/saved_project.dart';
export 'src/domain/source.dart';
export 'src/presentation/doc_oct_app.dart';
export 'src/presentation/editor/doc_model.dart';
export 'src/presentation/editor/editor_page.dart';
export 'src/presentation/editor/editor_toolbar.dart';
export 'src/presentation/editor/format_spec.dart';
export 'src/presentation/editor/paged_document.dart';
export 'src/presentation/loading/doc_oct_loading_page.dart';
export 'src/presentation/projects/saved_projects_page.dart';
export 'src/presentation/widgets/doc_scaffold.dart';
export 'src/presentation/widgets/doc_top_bar.dart';
export 'src/presentation/widgets/doc_widgets.dart';
export 'src/presentation/wizard/wizard_analysis_page.dart';
export 'src/presentation/wizard/wizard_primary_button.dart';
export 'src/presentation/wizard/wizard_setup_page.dart';
export 'src/presentation/wizard/wizard_shell.dart';
export 'src/presentation/wizard/wizard_welcome_page.dart';
export 'src/presentation/workspace/workspace_page.dart';
export 'src/theme/doc_tokens.dart';
