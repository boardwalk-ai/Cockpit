/// Doc Oct — academic document workstation (Flutter rewrite).
///
/// Doc Oct's exact web screens, restyled into the shared **borderless**
/// (Swiss · GitBook) design system from `cockpit_ui` (`BorderlessTheme`, Plus
/// Jakarta Sans, the floating `ThemeSwitcher`). Phase 1: loading screen +
/// wizard (welcome → setup → analysis) + workspace; the editor is Phase 2.
library;

export 'src/application/auth.dart';
export 'src/application/auth_providers.dart';
export 'src/application/backend_config.dart'
    show setAuthTokenSource, hasBackend, kDocOctApiBase;
export 'src/application/essays_service.dart';
export 'src/application/hein_service.dart';
export 'src/application/lily_service.dart';
export 'src/application/pdf_export.dart' show EssayInput, PdfStyle;
export 'src/application/pdf_export_app.dart';
export 'src/application/providers.dart';
export 'src/application/sources.dart';
export 'src/application/tools_service.dart';
export 'src/application/wizard_session.dart';
export 'src/domain/citation_templates.dart';
export 'src/domain/doc_dates.dart';
export 'src/domain/hein_analysis.dart';
export 'src/domain/lookup_result.dart';
export 'src/domain/outline.dart';
export 'src/domain/saved_project.dart';
export 'src/domain/source.dart';
export 'src/presentation/doc_oct_app.dart';
export 'src/presentation/editor/doc_model.dart';
export 'src/presentation/editor/editor_page.dart';
export 'src/presentation/editor/editor_panels.dart';
export 'src/presentation/editor/editor_toolbar.dart';
export 'src/presentation/editor/format_spec.dart';
export 'src/presentation/editor/indented_text.dart';
export 'src/presentation/editor/paged_document.dart';
export 'src/presentation/editor/tools_panel.dart';
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
