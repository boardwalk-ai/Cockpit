/// Doc Oct — academic document workstation (Flutter rewrite).
///
/// Doc Oct's exact web screens, restyled into the shared **borderless**
/// (Swiss · GitBook) design system from `cockpit_ui` (`BorderlessTheme`, Plus
/// Jakarta Sans, the floating `ThemeSwitcher`). Phase 1: loading screen +
/// wizard (welcome → setup → analysis) + workspace; the editor is Phase 2.
library;

export 'src/application/providers.dart';
export 'src/domain/saved_project.dart';
export 'src/presentation/doc_oct_app.dart';
export 'src/presentation/loading/doc_oct_loading_page.dart';
export 'src/presentation/projects/saved_projects_page.dart';
export 'src/presentation/widgets/doc_scaffold.dart';
export 'src/presentation/widgets/doc_top_bar.dart';
export 'src/presentation/widgets/doc_widgets.dart';
export 'src/presentation/wizard/wizard_shell.dart';
export 'src/presentation/wizard/wizard_welcome_page.dart';
export 'src/theme/doc_tokens.dart';
