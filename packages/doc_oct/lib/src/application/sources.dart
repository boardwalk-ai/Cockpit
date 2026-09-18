import '../domain/source.dart';

/// Placeholder sources so the References/Works Cited page renders while the
/// backend is unbuilt. **Seam:** the real list arrives from our Rust backend
/// (which owns the scraper + AI); the frontend never calls those APIs directly.
/// Swap this for a repository that deserializes backend responses into [Source].
const mockSources = <Source>[
  Source(
    url: 'https://www.nature.com/articles/s41586-021-03819-2',
    title: 'Highly accurate protein structure prediction with AlphaFold',
    author: 'Jumper, John',
    publishedYear: '2021',
    publisher: 'Nature',
    fullContent:
        'AlphaFold predicts protein structures with atomic accuracy even when '
        'no similar structure is known. The network combines a novel attention '
        'architecture with an iterative refinement of the predicted structure, '
        'reaching a median accuracy competitive with experimental methods across '
        'the majority of targets in the CASP14 assessment.',
  ),
  Source(
    url: 'https://www.pnas.org/doi/10.1073/pnas.1517384113',
    title: 'The spread of true and false news online',
    author: 'Vosoughi, Soroush',
    publishedYear: '2018',
    publisher: 'PNAS',
    fullContent:
        'A study of roughly 126,000 stories tweeted by about three million '
        'people found that false news spread significantly farther, faster, and '
        'more broadly than the truth in every category of information. Falsehood '
        'diffused faster than the truth, and the effects were more pronounced for '
        'false political news than for any other category.',
  ),
  Source(
    url: 'https://doi.org/10.1017/CBO9780511815355',
    title: 'The Cambridge History of the Cold War',
    author: 'Leffler, Melvyn P.',
    publishedYear: '2010',
    publisher: 'Cambridge University Press',
    fullContent:
        'The Cold War dominated international relations for more than four '
        'decades, shaping alliances, economies, and cultures across the globe. '
        'Its origins lay in the ideological rivalry between the United States and '
        'the Soviet Union, but its course was driven as much by miscalculation '
        'and mutual fear as by deliberate strategy.',
  ),
];
