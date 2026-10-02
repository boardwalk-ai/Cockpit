/// Canned GhostWriter run for previewing the UI without the backend.
///
/// Enabled with `--dart-define=GW_DEMO=true`; pressing Start then streams
/// [kDemoEssay] word by word instead of calling the API.
library;

const bool kGwDemo = bool.fromEnvironment('GW_DEMO');

const String kDemoEssay =
    'Coastal cities have always lived by the rhythm of the tide, but rising '
    'seas are changing what that rhythm means. High-tide flooding that once '
    'arrived a few days a year now reaches streets and basements dozens of '
    'times, even under clear skies.\n\n'
    'The cause is straightforward. As oceans warm they expand, and melting '
    'land ice adds more water. A higher baseline means every ordinary high '
    'tide starts closer to the top of the sea wall, so smaller storms do '
    'more damage than larger ones did a generation ago.\n\n'
    'Cities are responding in three ways. Some build barriers and raise '
    'roads. Others restore wetlands and dunes that absorb water naturally. '
    'A few have begun the harder conversation about moving homes and '
    'services away from the most exposed ground.\n\n'
    'None of these choices is cheap, and none works alone. The cities that '
    'cope best will be the ones that plan for the tide they expect in fifty '
    'years, not the one they remember.';

const String kDemoBibliography =
    'Sweet, W. V., et al. (2022). Global and regional sea level rise '
    'scenarios for the United States. NOAA Technical Report.\n\n'
    'Hino, M., Field, C. B., & Mach, K. J. (2017). Managed retreat as a '
    'response to natural hazard risk. Nature Climate Change, 7, 364–370.';

const List<Map<String, dynamic>> kDemoSources = [
  {
    'title':
        'Global and Regional Sea Level Rise Scenarios for the United States',
    'author': 'Sweet, W. V., et al.',
    'publisher': 'NOAA',
    'url': 'https://oceanservice.noaa.gov/hazards/sealevelrise/',
  },
  {
    'title': 'Managed retreat as a response to natural hazard risk',
    'author': 'Hino, M., Field, C. B., & Mach, K. J.',
    'publisher': 'Nature Climate Change',
    'url': 'https://www.nature.com/articles/nclimate3252',
  },
];
