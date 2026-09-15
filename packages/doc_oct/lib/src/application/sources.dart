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
  ),
  Source(
    url: 'https://www.pnas.org/doi/10.1073/pnas.1517384113',
    title: 'The spread of true and false news online',
    author: 'Vosoughi, Soroush',
    publishedYear: '2018',
    publisher: 'PNAS',
  ),
  Source(
    url: 'https://doi.org/10.1017/CBO9780511815355',
    title: 'The Cambridge History of the Cold War',
    author: 'Leffler, Melvyn P.',
    publishedYear: '2010',
    publisher: 'Cambridge University Press',
  ),
];
