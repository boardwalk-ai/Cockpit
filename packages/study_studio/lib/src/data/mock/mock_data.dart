import '../../domain/entities/flashcard.dart';
import '../../domain/entities/quiz_question.dart';
import '../../domain/entities/source.dart';
import '../../domain/entities/studio.dart';
import '../../domain/entities/topic.dart';

/// Canned studios that stand in for AI-extracted Study Objects until the
/// backend / AI provider is wired. Mirrors the examples in the brief.
List<Studio> buildMockStudios() {
  final now = DateTime.now();
  return [
    _biologyStudio(now),
    _mbrStudio(now),
  ];
}

Studio _biologyStudio(DateTime now) {
  const sid = 'bio';
  final topics = <Topic>[
    Topic(
      id: 'bio_dna',
      studioId: sid,
      title: 'DNA Replication',
      subject: 'Biology',
      definition:
          'The process by which a cell makes an identical copy of its DNA before division.',
      simpleExplanation:
          'DNA unzips into two strands, and each strand acts as a template to build a new matching strand — so one double helix becomes two.',
      detailedExplanation:
          'Helicase unwinds the double helix at the origin. Primase lays down RNA primers. DNA polymerase III extends the leading strand continuously and the lagging strand in Okazaki fragments, which ligase joins. The result is semi-conservative replication: each new molecule keeps one original strand.',
      whyItMatters:
          'Accurate replication preserves genetic information across cell divisions; errors here underlie mutations and cancer.',
      examples: [
        'Leading strand synthesized continuously toward the replication fork.',
        'Lagging strand built in short Okazaki fragments, later joined by ligase.',
      ],
      commonMistakes: [
        'Confusing replication (DNA→DNA) with transcription (DNA→RNA).',
        'Thinking both strands are synthesized continuously.',
      ],
      relatedTopicIds: ['bio_meiosis', 'bio_photo'],
      prerequisites: ['Base pairing (A-T, G-C)'],
      memoryHooks: ['"Semi-conservative" = each new helix keeps one OLD strand.'],
      sources: const [
        SourceReference(
          fileName: 'biology_chapter_4.pdf',
          page: 112,
          snippet: 'Replication is semi-conservative; each daughter molecule...',
        ),
      ],
      difficulty: 4,
      importance: 5,
      estimatedStudyTimeMinutes: 15,
      mastery: 0.35,
      flashcards: const [
        Flashcard(
          id: 'bio_dna_fc1',
          topicId: 'bio_dna',
          front: 'What enzyme unwinds the DNA double helix?',
          back: 'Helicase.',
          type: FlashcardType.definition,
        ),
        Flashcard(
          id: 'bio_dna_fc2',
          topicId: 'bio_dna',
          front: 'What are Okazaki fragments?',
          back: 'Short DNA segments synthesized on the lagging strand, later joined by ligase.',
          type: FlashcardType.process,
        ),
        Flashcard(
          id: 'bio_dna_fc3',
          topicId: 'bio_dna',
          front: 'Replication is described as ____.',
          back: 'Semi-conservative.',
          type: FlashcardType.definition,
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'bio_dna_q1',
          topicId: 'bio_dna',
          type: QuizType.multipleChoice,
          question: 'Which enzyme joins Okazaki fragments on the lagging strand?',
          choices: ['Helicase', 'Primase', 'DNA ligase', 'DNA polymerase I'],
          answer: 'DNA ligase',
          explanation: 'Ligase seals the nicks between adjacent Okazaki fragments.',
          difficulty: 3,
          relatedConcept: 'Lagging strand synthesis',
        ),
        QuizQuestion(
          id: 'bio_dna_q2',
          topicId: 'bio_dna',
          type: QuizType.trueFalse,
          question: 'DNA replication produces two molecules, each with one old and one new strand.',
          choices: ['True', 'False'],
          answer: 'True',
          explanation: 'This is the definition of semi-conservative replication.',
          difficulty: 2,
        ),
      ],
    ),
    Topic(
      id: 'bio_meiosis',
      studioId: sid,
      title: 'Meiosis',
      subject: 'Biology',
      definition:
          'A two-stage cell division that produces four genetically varied haploid gametes.',
      simpleExplanation:
          'One cell divides twice to make four sex cells, each with half the chromosomes and a unique mix of genes.',
      detailedExplanation:
          'Meiosis I separates homologous chromosomes (reducing the count from diploid to haploid); crossing over in prophase I and independent assortment create variation. Meiosis II separates sister chromatids, similar to mitosis.',
      whyItMatters:
          'Meiosis maintains chromosome number across generations and is the source of genetic diversity.',
      examples: [
        'Crossing over swaps segments between homologous chromosomes.',
        'Independent assortment shuffles maternal/paternal chromosomes.',
      ],
      commonMistakes: [
        'Mixing up meiosis I (homologs separate) with meiosis II (sisters separate).',
      ],
      relatedTopicIds: ['bio_dna'],
      prerequisites: ['Mitosis', 'Chromosome structure'],
      memoryHooks: ['MeiOSIS makes Sex cells; mitOSIS makes body cells.'],
      sources: const [
        SourceReference(
          fileName: 'biology_chapter_4.pdf',
          page: 130,
          snippet: 'Meiosis I is the reductional division...',
        ),
      ],
      difficulty: 4,
      importance: 4,
      estimatedStudyTimeMinutes: 12,
      mastery: 0.5,
      flashcards: const [
        Flashcard(
          id: 'bio_mei_fc1',
          topicId: 'bio_meiosis',
          front: 'How many cells result from meiosis?',
          back: 'Four haploid cells.',
        ),
        Flashcard(
          id: 'bio_mei_fc2',
          topicId: 'bio_meiosis',
          front: 'When does crossing over occur?',
          back: 'Prophase I.',
          type: FlashcardType.process,
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'bio_mei_q1',
          topicId: 'bio_meiosis',
          type: QuizType.multipleChoice,
          question: 'Homologous chromosomes separate during which phase?',
          choices: ['Anaphase I', 'Anaphase II', 'Metaphase II', 'Telophase II'],
          answer: 'Anaphase I',
          explanation: 'Meiosis I is the reductional division separating homologs.',
          difficulty: 3,
        ),
      ],
    ),
    Topic(
      id: 'bio_photo',
      studioId: sid,
      title: 'Photosynthesis',
      subject: 'Biology',
      definition:
          'The process plants use to convert light energy into chemical energy stored in glucose.',
      simpleExplanation:
          'Plants capture sunlight to turn carbon dioxide and water into sugar and oxygen.',
      detailedExplanation:
          'Light-dependent reactions in the thylakoid membranes produce ATP and NADPH and release O2. The Calvin cycle in the stroma uses ATP/NADPH to fix CO2 into glucose.',
      whyItMatters:
          'Photosynthesis is the foundation of most food chains and the source of atmospheric oxygen.',
      examples: ['6CO2 + 6H2O + light → C6H12O6 + 6O2'],
      commonMistakes: ['Assuming the Calvin cycle needs light directly (it uses ATP/NADPH).'],
      relatedTopicIds: ['bio_dna'],
      prerequisites: ['Cell organelles'],
      memoryHooks: ['Calvin cycle = the "dark" reactions, but still daytime-powered.'],
      sources: const [
        SourceReference(
          fileName: 'biology_chapter_4.pdf',
          page: 88,
          snippet: 'The Calvin cycle fixes carbon using ATP and NADPH...',
        ),
      ],
      difficulty: 3,
      importance: 4,
      estimatedStudyTimeMinutes: 10,
      mastery: 0.72,
      flashcards: const [
        Flashcard(
          id: 'bio_photo_fc1',
          topicId: 'bio_photo',
          front: 'Where does the Calvin cycle occur?',
          back: 'In the stroma of the chloroplast.',
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'bio_photo_q1',
          topicId: 'bio_photo',
          type: QuizType.fillBlank,
          question: 'The light reactions release ____ as a by-product.',
          answer: 'oxygen',
          explanation: 'Water is split, releasing O2.',
          difficulty: 2,
        ),
      ],
    ),
  ];

  return Studio(
    id: sid,
    title: 'Biology Midterm Studio',
    subject: 'Biology',
    createdAt: now.subtract(const Duration(days: 6)),
    updatedAt: now.subtract(const Duration(days: 1)),
    lastStudied: now.subtract(const Duration(days: 1)),
    sourceFiles: const [
      SourceFile(id: 'f1', name: 'biology_chapter_4.pdf', type: SourceFileType.pdf),
      SourceFile(id: 'f2', name: 'lecture_slides.pptx', type: SourceFileType.pptx),
      SourceFile(id: 'f3', name: 'handwritten_notes.png', type: SourceFileType.image),
    ],
    topics: topics,
  );
}

Studio _mbrStudio(DateTime now) {
  const sid = 'mbr';
  final topics = <Topic>[
    Topic(
      id: 'mbr_ahl',
      studioId: sid,
      title: 'AHL — Missing Bag File',
      subject: 'Baggage Handling',
      definition:
          'An AHL (Advice if Hold) is the file created when a passenger reports a bag that has not arrived.',
      simpleExplanation:
          'When a passenger says their bag is missing and it is not on the carousel or already forwarded, you open an AHL to start tracing it.',
      detailedExplanation:
          'The AHL records passenger details, bag description, routing, and tag number, and feeds the worldwide tracing system so any station can match a found bag to the report.',
      whyItMatters:
          'The AHL is the entry point of the tracing workflow — without it, a mishandled bag cannot be matched and returned.',
      examples: [
        'Passenger arrives, bag not on carousel, no forwarding record → create AHL.',
      ],
      commonMistakes: [
        'Creating an OHD (found bag) instead of an AHL (missing bag).',
        'Skipping the tag number, which breaks the match.',
      ],
      relatedTopicIds: ['mbr_ohd', 'mbr_carousel'],
      prerequisites: ['Bag tag basics'],
      memoryHooks: ['AHL = "A bag has Left the passenger" → missing.'],
      sources: const [
        SourceReference(
          fileName: 'mbr_training_manual.pdf',
          page: 14,
          snippet: 'When a bag is not located, create an AHL to begin tracing...',
        ),
      ],
      difficulty: 2,
      importance: 5,
      estimatedStudyTimeMinutes: 8,
      mastery: 0.58,
      flashcards: const [
        Flashcard(
          id: 'mbr_ahl_fc1',
          topicId: 'mbr_ahl',
          front: 'What file is created for a missing bag?',
          back: 'An AHL (missing bag file).',
        ),
        Flashcard(
          id: 'mbr_ahl_fc2',
          topicId: 'mbr_ahl',
          front: 'What is the most critical field for matching?',
          back: 'The bag tag number.',
          type: FlashcardType.mistake,
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'mbr_ahl_q1',
          topicId: 'mbr_ahl',
          type: QuizType.multipleChoice,
          question:
              'A passenger reports a missing bag. It is not on the carousel and not forwarded. Which file do you create first?',
          choices: ['OHD', 'AHL', 'DPR', 'PIR closure'],
          answer: 'AHL',
          explanation: 'A missing (not located) bag starts with an AHL.',
          difficulty: 2,
          relatedConcept: 'Tracing workflow entry point',
        ),
      ],
    ),
    Topic(
      id: 'mbr_ohd',
      studioId: sid,
      title: 'OHD — Found Bag File',
      subject: 'Baggage Handling',
      definition:
          'An OHD (On-Hand) is the file created for an unclaimed bag found without an owner.',
      simpleExplanation:
          'When you find a bag nobody claimed, you log it as an OHD so it can be matched to a missing-bag report.',
      detailedExplanation:
          'The OHD captures the found bag\'s tag, description and location. The tracing system cross-matches OHDs against AHLs to reunite bags with passengers.',
      whyItMatters:
          'OHDs are the other half of tracing — matches happen between AHLs (missing) and OHDs (found).',
      examples: ['Unclaimed bag on carousel after all passengers leave → create OHD.'],
      commonMistakes: ['Confusing OHD (found) with AHL (missing).'],
      relatedTopicIds: ['mbr_ahl'],
      prerequisites: ['Bag tag basics'],
      memoryHooks: ['OHD = On-Hand → you HAVE the bag.'],
      sources: const [
        SourceReference(
          fileName: 'mbr_training_manual.pdf',
          page: 20,
          snippet: 'A found, unclaimed bag is recorded as an OHD...',
        ),
      ],
      difficulty: 2,
      importance: 4,
      estimatedStudyTimeMinutes: 6,
      mastery: 0.4,
      flashcards: const [
        Flashcard(
          id: 'mbr_ohd_fc1',
          topicId: 'mbr_ohd',
          front: 'What file is created for a found, unclaimed bag?',
          back: 'An OHD (On-Hand) file.',
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'mbr_ohd_q1',
          topicId: 'mbr_ohd',
          type: QuizType.trueFalse,
          question: 'An OHD is matched against AHLs to reunite bags with passengers.',
          choices: ['True', 'False'],
          answer: 'True',
          explanation: 'Tracing matches found (OHD) against missing (AHL).',
          difficulty: 2,
        ),
      ],
    ),
    Topic(
      id: 'mbr_carousel',
      studioId: sid,
      title: 'Carousel & Forwarding Check',
      subject: 'Baggage Handling',
      definition:
          'The verification steps confirming whether a bag is on the carousel or already forwarded before opening a file.',
      simpleExplanation:
          'Before declaring a bag missing, check the carousel and the forwarding records — it may not actually be lost.',
      detailedExplanation:
          'Standard procedure: confirm the bag is not on the belt, then check forwarding/rush-tag records. Only if both are negative do you create an AHL.',
      whyItMatters:
          'Skipping these checks creates false AHLs and clutters the tracing system.',
      examples: ['Bag was rush-tagged on an earlier flight → no AHL needed.'],
      commonMistakes: ['Opening an AHL before checking forwarding records.'],
      relatedTopicIds: ['mbr_ahl'],
      prerequisites: [],
      memoryHooks: ['Check belt → check forwarding → THEN file.'],
      sources: const [
        SourceReference(
          fileName: 'mbr_training_manual.pdf',
          page: 12,
          snippet: 'Verify the bag is not on the carousel or forwarded before filing...',
        ),
      ],
      difficulty: 1,
      importance: 4,
      estimatedStudyTimeMinutes: 5,
      mastery: 0.8,
      flashcards: const [
        Flashcard(
          id: 'mbr_car_fc1',
          topicId: 'mbr_carousel',
          front: 'What two checks come before filing an AHL?',
          back: 'Carousel check and forwarding-record check.',
          type: FlashcardType.process,
        ),
      ],
      quizQuestions: const [
        QuizQuestion(
          id: 'mbr_car_q1',
          topicId: 'mbr_carousel',
          type: QuizType.shortAnswer,
          question: 'Before creating an AHL, which records must you check besides the carousel?',
          answer: 'forwarding',
          explanation: 'Always confirm the bag was not already forwarded/rush-tagged.',
          difficulty: 1,
        ),
      ],
    ),
  ];

  return Studio(
    id: sid,
    title: 'MBR Training Studio',
    subject: 'Baggage Handling',
    createdAt: now.subtract(const Duration(days: 3)),
    updatedAt: now,
    lastStudied: now,
    sourceFiles: const [
      SourceFile(id: 'm1', name: 'mbr_training_manual.pdf', type: SourceFileType.pdf),
    ],
    topics: topics,
  );
}
