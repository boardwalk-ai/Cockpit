"""Topic banks for the sample study-materials generator.

Each subject has several distinct topics so generated files can vary in title,
structure, examples, and wording instead of repeating one template.
"""

from __future__ import annotations

from typing import Any

Topic = dict[str, Any]


def _topic(
    *,
    slug: str,
    title: str,
    overview: str,
    terms: list[tuple[str, str]],
    explanations: list[tuple[str, str]],
    bullets: list[str],
    examples: list[str],
    worked: list[tuple[str, str]],
    pitfalls: list[str],
    review: list[str],
) -> Topic:
    return {
        "slug": slug,
        "title": title,
        "overview": overview,
        "terms": terms,
        "explanations": explanations,
        "bullets": bullets,
        "examples": examples,
        "worked": worked,
        "pitfalls": pitfalls,
        "review": review,
    }


BIOLOGY: list[Topic] = [
    _topic(
        slug="photosynthesis",
        title="Photosynthesis and Chloroplast Function",
        overview=(
            "Photosynthesis converts light energy into chemical energy stored in sugars. "
            "It is the entry point for nearly all energy that moves through ecosystems, "
            "and it also releases the oxygen that aerobic organisms depend on. These notes "
            "separate the light-dependent reactions from the Calvin cycle so you can track "
            "where ATP, NADPH, and carbon actually change form."
        ),
        terms=[
            ("Chloroplast", "Organelle in plant and algal cells where photosynthesis occurs."),
            ("Thylakoid", "Membrane sac that holds photosystems and the photosynthetic electron-transport chain."),
            ("Calvin cycle", "Light-independent pathway that fixes CO2 into carbohydrates in the stroma."),
            ("NADPH", "Reduced electron carrier that delivers high-energy electrons to carbon fixation."),
        ],
        explanations=[
            (
                "Light-dependent reactions",
                "Photosystem II absorbs photons and splits water, releasing O2, protons, and electrons. "
                "Electrons travel through plastoquinone, the cytochrome b6f complex, and plastocyanin to "
                "photosystem I. The proton gradient drives ATP synthase, while photosystem I reduces NADP+ "
                "to NADPH. Remember the products that leave the thylakoid membrane: ATP, NADPH, and oxygen.",
            ),
            (
                "Carbon fixation",
                "Rubisco attaches CO2 to ribulose bisphosphate (RuBP). The resulting 3-phosphoglycerate is "
                "reduced to G3P using ATP and NADPH. Most G3P regenerates RuBP; some exits to make glucose "
                "and other sugars. Rubisco can also bind O2, which starts photorespiration and wastes energy "
                "in hot, dry conditions when stomata close.",
            ),
            (
                "Why C4 and CAM plants differ",
                "C4 plants concentrate CO2 around rubisco using a spatial separation between mesophyll and "
                "bundle-sheath cells. CAM plants open stomata at night and store malate, then fix carbon by "
                "day with closed stomata. Both strategies reduce photorespiration when water is scarce.",
            ),
        ],
        bullets=[
            "Light reactions: H2O + light → O2 + ATP + NADPH.",
            "Calvin cycle: CO2 + ATP + NADPH → G3P (and regenerated RuBP).",
            "Limiting factors include light intensity, CO2 concentration, and temperature.",
            "Stomatal closure trades water conservation against CO2 supply.",
        ],
        examples=[
            "A shaded understory plant has a lower light-compensation point than a sun leaf on the same species.",
            "On a hot afternoon, a C3 crop may show reduced net photosynthesis even though light is abundant.",
        ],
        worked=[
            (
                "Tracking atoms through the light reactions",
                "Question: Where do the oxygen atoms in O2 come from?\n"
                "1. Water is the electron donor at photosystem II.\n"
                "2. 2 H2O → 4 H+ + 4 e− + O2.\n"
                "3. The O2 is released; the electrons replace those lost by chlorophyll.\n"
                "Answer: the oxygen gas comes from water, not from carbon dioxide.",
            ),
        ],
        pitfalls=[
            "Do not say the Calvin cycle happens only in the dark; it is light-independent but usually runs in the day because it needs ATP and NADPH.",
            "Chlorophyll absorbs red and blue light; green light is mostly reflected, which is why leaves look green.",
        ],
        review=[
            "Name the three products of the light-dependent reactions.",
            "Explain why photorespiration increases when stomata close.",
            "Contrast C3, C4, and CAM carbon-fixation strategies in one sentence each.",
        ],
    ),
    _topic(
        slug="membrane-transport",
        title="Cell Membrane Transport",
        overview=(
            "The plasma membrane is a selectively permeable phospholipid bilayer studded with proteins. "
            "Cells stay alive by controlling what crosses that barrier. These notes compare passive and "
            "active routes and then apply them to osmosis problems you will see on quizzes."
        ),
        terms=[
            ("Diffusion", "Net movement of a solute from higher to lower concentration."),
            ("Osmosis", "Net movement of water across a semipermeable membrane toward higher solute concentration."),
            ("Facilitated diffusion", "Passive transport through a channel or carrier protein."),
            ("Sodium-potassium pump", "Active transporter that moves 3 Na+ out and 2 K+ in per ATP hydrolyzed."),
        ],
        explanations=[
            (
                "Passive versus active transport",
                "Passive transport follows an electrochemical gradient and does not consume ATP directly. "
                "Simple diffusion handles small nonpolar molecules such as O2 and CO2. Polar or charged "
                "solutes need proteins. Active transport moves solutes against a gradient and requires energy, "
                "either ATP (primary) or an existing ion gradient (secondary).",
            ),
            (
                "Tonicity and cell volume",
                "In an animal cell, a hypotonic bath causes swelling and possible lysis; a hypertonic bath "
                "causes crenation. Plant cells are protected by a wall: hypotonic conditions create turgor, "
                "while hypertonic conditions cause plasmolysis. Always identify the solute that cannot cross "
                "before you predict water movement.",
            ),
            (
                "Coupled transport",
                "The Na+/K+ pump builds a sodium gradient. A sodium-glucose cotransporter can then drag "
                "glucose into the cell against its concentration gradient. That is secondary active transport: "
                "glucose 'uphill' is paid for by sodium 'downhill'.",
            ),
        ],
        bullets=[
            "Nonpolar, small molecules cross the bilayer most easily.",
            "Channels are faster than carriers but less specific in many cases.",
            "Osmolarity counts all solute particles; tonicity describes the effect on cell volume.",
            "Endocytosis and exocytosis move bulk cargo in vesicles.",
        ],
        examples=[
            "Oxygen entering a respiring muscle cell is simple diffusion.",
            "Glucose uptake in the gut uses sodium-coupled secondary active transport.",
        ],
        worked=[
            (
                "Predicting osmosis",
                "A red blood cell is placed in 0.9% NaCl (isotonic) versus distilled water.\n"
                "1. In 0.9% NaCl, net water movement is roughly zero; volume is stable.\n"
                "2. In distilled water, extracellular solute is near zero, so water rushes in.\n"
                "3. Without a cell wall, the cell swells and may burst.\n"
                "Conclusion: distilled water is hypotonic to the erythrocyte.",
            ),
        ],
        pitfalls=[
            "Hypertonic refers to the solution, not the cell. Say 'the bath is hypertonic to the cell'.",
            "Facilitated diffusion is still passive; a protein does not automatically mean ATP is used.",
        ],
        review=[
            "Classify O2, glucose, and Na+ by their typical crossing mechanism.",
            "Why does the Na+/K+ pump contribute to membrane potential?",
            "What happens to a plant cell in a concentrated sucrose solution?",
        ],
    ),
    _topic(
        slug="dna-replication",
        title="DNA Replication",
        overview=(
            "Before a cell divides, it copies its genome so each daughter cell receives a complete set of "
            "instructions. Replication is semi-conservative: each new helix keeps one parental strand. "
            "The enzymology is a favorite exam topic because leading and lagging strands are not symmetric."
        ),
        terms=[
            ("Helicase", "Enzyme that unwinds the double helix at the replication fork."),
            ("Primase", "RNA polymerase that lays short primers DNA polymerase can extend."),
            ("Okazaki fragment", "Short DNA piece synthesized on the lagging strand."),
            ("Ligase", "Enzyme that seals nicks by forming phosphodiester bonds."),
        ],
        explanations=[
            (
                "Directionality",
                "DNA polymerase adds nucleotides only to a 3' OH, so synthesis is always 5'→3'. The leading "
                "strand is made continuously toward the fork. The lagging strand is made in pieces away from "
                "the fork as new template is exposed. That single chemical constraint explains almost every "
                "oddity of the replication fork.",
            ),
            (
                "Proofreading and primers",
                "DNA polymerase III (in bacteria) has 3'→5' exonuclease proofreading. RNA primers are later "
                "removed and replaced with DNA; ligase then joins fragments. Mutations that disable proofreading "
                "raise the mutation rate and are used experimentally to study evolution.",
            ),
            (
                "Eukaryotic complications",
                "Linear chromosomes shorten unless telomerase extends the 3' overhang. Multiple origins let "
                "long eukaryotic chromosomes finish replication in a reasonable time. Licensing factors prevent "
                "an origin from firing twice in one cell cycle.",
            ),
        ],
        bullets=[
            "Semi-conservative: one old strand + one new strand per daughter helix.",
            "Leading strand: continuous; lagging strand: Okazaki fragments.",
            "Primers are RNA; they must be replaced before ligation.",
            "Telomerase is a reverse transcriptase that carries an RNA template.",
        ],
        examples=[
            "Meselson and Stahl used 15N labeling to show semi-conservative replication in E. coli.",
            "A ligase-deficient mutant accumulates nicked lagging strands.",
        ],
        worked=[
            (
                "Labeling the fork",
                "Template sequence 3'-ATCG-5' is being copied.\n"
                "1. New DNA is made 5'→3', so the new strand reads 5'-TAGC-3'.\n"
                "2. If this template is on the lagging side, primase must start a new primer as the fork opens.\n"
                "3. The previous Okazaki fragment will be joined after primer removal.\n"
                "Check: antiparallel pairing and 5'→3' synthesis both hold.",
            ),
        ],
        pitfalls=[
            "Polymerase does not synthesize 3'→5' on the lagging strand; the fragments themselves are still 5'→3'.",
            "Helicase unwinds; gyrase/topoisomerase relieves supercoils ahead of the fork.",
        ],
        review=[
            "Why are primers required at all?",
            "List the enzymes needed to finish one Okazaki fragment.",
            "What problem do telomeres solve in linear chromosomes?",
        ],
    ),
    _topic(
        slug="mendelian-genetics",
        title="Mendelian Genetics and Punnett Squares",
        overview=(
            "Mendel showed that discrete hereditary factors segregate and assort independently. Modern "
            "language maps those factors onto genes and alleles. These notes walk from vocabulary to "
            "monohybrid and dihybrid predictions, then flag the cases where Mendel's ratios fail."
        ),
        terms=[
            ("Allele", "A variant form of a gene."),
            ("Genotype", "The allele combination an organism carries."),
            ("Phenotype", "The observable trait produced by genotype and environment."),
            ("Independent assortment", "Alleles of different genes segregate independently if they are unlinked."),
        ],
        explanations=[
            (
                "Segregation",
                "In meiosis I, homologous chromosomes separate, so a heterozygote Aa produces gametes that "
                "are half A and half a. A Punnett square is just a structured way of combining those gamete "
                "frequencies. A 3:1 phenotypic ratio in the F2 is the signature of a single autosomal gene "
                "with complete dominance.",
            ),
            (
                "Dihybrid crosses",
                "For two unlinked genes, an F1 double heterozygote produces four gamete types in equal "
                "frequency. The F2 phenotypic ratio is 9:3:3:1. Linkage, lethality, epistasis, and sex linkage "
                "all distort that classic ratio, which is why you should never assume 9:3:3:1 without evidence.",
            ),
            (
                "Test crosses",
                "Crossing an unknown dominant phenotype with a homozygous recessive tester reveals the unknown "
                "genotype. If any recessive offspring appear, the unknown parent was heterozygous. This is still "
                "the cleanest experimental design for mapping dominance.",
            ),
        ],
        bullets=[
            "AA and Aa look the same if A is completely dominant.",
            "A test cross of Aa × aa yields 1:1.",
            "Linked genes travel together unless crossing over separates them.",
            "Pedigrees: recessive traits can skip generations; dominant traits generally do not.",
        ],
        examples=[
            "Seed shape in peas: round (R) dominant to wrinkled (r).",
            "Human ABO blood groups are a multiple-allele system with codominance of IA and IB.",
        ],
        worked=[
            (
                "Monohybrid prediction",
                "Parents: heterozygous tall × heterozygous tall (Tt × Tt). Tall is dominant.\n"
                "1. Gametes: each parent makes 1/2 T and 1/2 t.\n"
                "2. Offspring genotypes: 1/4 TT, 1/2 Tt, 1/4 tt.\n"
                "3. Phenotypes: 3/4 tall, 1/4 short.\n"
                "If 160 offspring are scored, expect about 120 tall and 40 short.",
            ),
        ],
        pitfalls=[
            "A 3:1 ratio is phenotypic, not genotypic. The genotypic ratio is 1:2:1.",
            "Do not use a Punnett square for linked genes without recombination frequencies.",
        ],
        review=[
            "What cross distinguishes TT from Tt?",
            "Why does linkage violate independent assortment?",
            "Write the expected F2 ratio for a dihybrid with complete dominance and no linkage.",
        ],
    ),
    _topic(
        slug="cellular-respiration",
        title="Cellular Respiration",
        overview=(
            "Cellular respiration harvests energy from organic molecules and stores it in ATP. Glycolysis, "
            "pyruvate oxidation, the citric acid cycle, and oxidative phosphorylation form a pipeline. "
            "Knowing where ATP, NADH, and CO2 appear is more useful than memorizing every intermediate."
        ),
        terms=[
            ("Glycolysis", "Ten-step pathway in the cytosol that splits glucose into two pyruvate."),
            ("NADH", "Reduced electron carrier that donates electrons to the respiratory chain."),
            ("Chemiosmosis", "Use of a proton gradient to drive ATP synthesis."),
            ("Fermentation", "Cytosolic pathway that regenerates NAD+ when oxygen is unavailable."),
        ],
        explanations=[
            (
                "From glucose to pyruvate",
                "Glycolysis invests 2 ATP and returns 4 ATP plus 2 NADH, for a net of 2 ATP per glucose. "
                "It does not require oxygen. In aerobic cells, pyruvate enters mitochondria and is converted "
                "to acetyl-CoA, releasing CO2 and more NADH.",
            ),
            (
                "The electron-transport chain",
                "NADH and FADH2 donate electrons to complexes in the inner mitochondrial membrane. As electrons "
                "move to O2, protons are pumped into the intermembrane space. ATP synthase lets protons flow "
                "back in, coupling that flow to ATP production. Oxygen is the terminal electron acceptor.",
            ),
            (
                "Aerobic yield versus fermentation",
                "Complete oxidation of glucose yields far more ATP than glycolysis alone, on the order of "
                "about 30 ATP in many eukaryotic estimates. Lactic acid or alcoholic fermentation yields only "
                "the net 2 ATP from glycolysis, but it keeps NAD+ available so glycolysis can continue.",
            ),
        ],
        bullets=[
            "CO2 is released in pyruvate oxidation and the citric acid cycle, not in glycolysis.",
            "Cyanide blocks cytochrome oxidase and stops electron flow to oxygen.",
            "Uncouplers leak protons and produce heat instead of ATP.",
            "Muscle cells use lactate fermentation during intense anaerobic effort.",
        ],
        examples=[
            "Yeast in bread dough ferment and release CO2, which makes the dough rise.",
            "Brown fat uncouples oxidative phosphorylation to generate heat in infants.",
        ],
        worked=[
            (
                "Counting NADH from one glucose",
                "1. Glycolysis: 2 NADH.\n"
                "2. Pyruvate → acetyl-CoA (two pyruvates): 2 NADH.\n"
                "3. Citric acid cycle (two turns): 6 NADH and 2 FADH2.\n"
                "Total: 10 NADH + 2 FADH2 before the chain. Exact ATP per NADH varies with shuttle systems.",
            ),
        ],
        pitfalls=[
            "Mitochondria are not required for glycolysis; it is cytosolic.",
            "Oxygen does not combine with carbon to make CO2 in the chain; CO2 already left in earlier steps. Oxygen becomes water.",
        ],
        review=[
            "Where is the proton gradient built in mitochondria?",
            "Why does fermentation exist if it makes so little ATP?",
            "Which stages produce CO2?",
        ],
    ),
    _topic(
        slug="natural-selection",
        title="Natural Selection and Speciation",
        overview=(
            "Evolution is change in allele frequencies in a population. Natural selection is one mechanism, "
            "and it is not random: it favors traits that raise reproductive success in a given environment. "
            "These notes connect Darwin's logic to population genetics and then to how new species form."
        ),
        terms=[
            ("Fitness", "Relative contribution of a genotype to the next generation."),
            ("Adaptation", "A trait shaped by selection that improves current fitness."),
            ("Gene flow", "Movement of alleles between populations via migration or pollen."),
            ("Reproductive isolation", "Barriers that prevent gene exchange between groups."),
        ],
        explanations=[
            (
                "Requirements for selection",
                "Selection needs variation, heritability, and differential reproductive success. Mutation and "
                "recombination supply variation; selection sorts it. Drift also changes frequencies, especially "
                "in small populations, but drift is not biased toward adaptation.",
            ),
            (
                "Modes of selection",
                "Directional selection shifts the mean. Stabilizing selection favors intermediates. Disruptive "
                "selection favors extremes and can contribute to polymorphism. Sexual selection can produce "
                "traits that look wasteful for survival but help in mating.",
            ),
            (
                "Speciation",
                "Allopatric speciation begins with geographic separation. Sympatric speciation occurs without "
                "it, for example via polyploidy in plants. Prezygotic barriers (timing, behavior, gametes) act "
                "before a zygote forms; postzygotic barriers (hybrid inviability or sterility) act after.",
            ),
        ],
        bullets=[
            "Individuals do not evolve; populations do.",
            "Selection acts on phenotypes, but only heritable differences change the next generation.",
            "Homologous structures reflect common ancestry; analogous structures reflect similar selection.",
            "Hardy-Weinberg is a null model: no selection, drift, mutation, migration, or nonrandom mating.",
        ],
        examples=[
            "Peppered moths: darker morphs increased when soot darkened tree trunks.",
            "Antibiotic resistance is directional selection in bacterial populations.",
        ],
        worked=[
            (
                "Hardy-Weinberg check",
                "A gene has alleles A and a. Frequency of a is q = 0.3, so p = 0.7.\n"
                "Expected genotype frequencies: p² = 0.49 AA, 2pq = 0.42 Aa, q² = 0.09 aa.\n"
                "If a sample of 200 has 30 aa individuals (0.15), aa is more common than 0.09.\n"
                "The population is not in Hardy-Weinberg; some assumption is violated.",
            ),
        ],
        pitfalls=[
            "Survival of the fittest does not mean strongest; it means highest reproductive success.",
            "Evolution is not goal-directed. Traits are not 'for the good of the species' by default.",
        ],
        review=[
            "List the five Hardy-Weinberg assumptions.",
            "Contrast allopatric and sympatric speciation.",
            "Why can sexual selection conflict with survival?",
        ],
    ),
    _topic(
        slug="enzyme-function",
        title="Enzymes and Reaction Rates",
        overview=(
            "Enzymes are biological catalysts, usually proteins, that speed reactions by lowering activation "
            "energy. They do not change the equilibrium; they help the reaction reach equilibrium faster. "
            "Rate curves, inhibitors, and environmental effects are the core exam skills."
        ),
        terms=[
            ("Active site", "Pocket where substrate binds and catalysis happens."),
            ("Activation energy", "Energy barrier that must be crossed for reactants to become products."),
            ("Km", "Substrate concentration at half-maximal velocity; a rough inverse measure of affinity."),
            ("Allosteric regulation", "Control by binding a site other than the active site."),
        ],
        explanations=[
            (
                "How enzymes speed reactions",
                "Binding orients substrates, strains bonds, and may provide acid-base or covalent catalysis. "
                "The enzyme-substrate complex is transient. After product release the enzyme is unchanged and "
                "can run another cycle. Temperature raises molecular motion until denaturation collapses the fold.",
            ),
            (
                "Michaelis-Menten behavior",
                "At low substrate, rate rises almost linearly. At high substrate, enzyme is saturated and rate "
                "approaches Vmax. Km is the [S] that gives Vmax/2. A small Km often means the enzyme is busy "
                "even when substrate is scarce.",
            ),
            (
                "Inhibitors",
                "Competitive inhibitors bind the active site and raise apparent Km; Vmax is unchanged if you "
                "add enough substrate. Noncompetitive inhibitors lower Vmax. Many drugs are designed as "
                "reversible competitive inhibitors; some toxins bind irreversibly.",
            ),
        ],
        bullets=[
            "pH changes can protonate catalytic residues and also denature the protein.",
            "Cofactors may be metal ions; coenzymes are organic helpers such as NAD+.",
            "Feedback inhibition is common in biosynthetic pathways.",
            "A sigmoidal curve often signals cooperative allosteric enzymes.",
        ],
        examples=[
            "Catalase splitting hydrogen peroxide is a classic high-turnover enzyme.",
            "Methotrexate competitively inhibits dihydrofolate reductase in some chemotherapy regimens.",
        ],
        worked=[
            (
                "Reading an inhibitor plot",
                "Without inhibitor, Vmax = 100 units and Km = 2 mM.\n"
                "With inhibitor, Vmax is still 100 but Km = 8 mM.\n"
                "1. Vmax unchanged ⇒ not reducing the number of working enzymes at saturation.\n"
                "2. Km increased ⇒ more substrate is needed to reach half-max.\n"
                "3. Pattern matches competitive inhibition.",
            ),
        ],
        pitfalls=[
            "Enzymes do not make an endergonic reaction exergonic; they only change the path.",
            "Boiling an enzyme usually destroys activity; that is denaturation, not 'using it up'.",
        ],
        review=[
            "Sketch rate versus [S] and mark Vmax and Km.",
            "How does a competitive inhibitor change the Lineweaver-Burk intercepts?",
            "Why does each enzyme have an optimal pH?",
        ],
    ),
    _topic(
        slug="immune-response",
        title="Innate and Adaptive Immunity",
        overview=(
            "The immune system distinguishes self from non-self and remembers previous infections. Innate "
            "defenses act within hours; adaptive defenses are slower but specific and long-lived. These notes "
            "follow an antigen from barrier tissues to antibodies and cytotoxic T cells."
        ),
        terms=[
            ("Antigen", "Molecule that can be recognized by a lymphocyte receptor or antibody."),
            ("Antibody", "Y-shaped protein secreted by plasma cells that binds a specific epitope."),
            ("MHC", "Surface proteins that display peptide fragments to T cells."),
            ("Memory cell", "Long-lived lymphocyte that mounts a faster response on re-exposure."),
        ],
        explanations=[
            (
                "Innate front line",
                "Skin, mucus, and acid are barriers. Phagocytes engulf microbes. Complement punches holes and "
                "tags pathogens. Interferons warn neighboring cells of viral infection. Inflammation recruits "
                "cells and is helpful in the short term, damaging if chronic.",
            ),
            (
                "Adaptive branches",
                "B cells recognize native antigen and can become plasma cells. Helper T cells (CD4) coordinate "
                "via cytokines after seeing antigen on MHC II. Cytotoxic T cells (CD8) kill infected cells "
                "displaying antigen on MHC I. Clonal selection expands the rare matching clone.",
            ),
            (
                "Vaccination logic",
                "A vaccine presents antigen without causing full disease, generating memory. Boosters raise "
                "affinity and memory-cell numbers. Herd immunity lowers transmission when coverage is high "
                "enough that chains of infection die out.",
            ),
        ],
        bullets=[
            "Innate: fast, limited specificity, no lasting clonal memory.",
            "Adaptive: slower first time, highly specific, memory.",
            "Humoral immunity is antibody-mediated; cell-mediated immunity is T-cell driven.",
            "Autoimmunity is a failure of self-tolerance.",
        ],
        examples=[
            "A tetanus booster is given because antibody titers wane.",
            "HIV depletes CD4 T cells and collapses coordination of the adaptive response.",
        ],
        worked=[
            (
                "Primary versus secondary response",
                "Day 0: first exposure to antigen X. IgM appears around day 7, then IgG.\n"
                "Day 40: second exposure.\n"
                "1. Memory B cells are already present.\n"
                "2. IgG rises faster, higher, and with greater affinity.\n"
                "3. That is why two-dose vaccine schedules are common.",
            ),
        ],
        pitfalls=[
            "Antibiotics target bacteria, not viruses; they are not interchangeable with vaccines.",
            "Fever is a regulated host response, not just a malfunction.",
        ],
        review=[
            "Match MHC I and MHC II to the T-cell types that read them.",
            "What does clonal selection mean in one sentence?",
            "Why can a person be immune without currently having high circulating antibody?",
        ],
    ),
]

HISTORY: list[Topic] = [
    _topic(
        slug="french-revolution",
        title="The French Revolution, 1789–1799",
        overview=(
            "The French Revolution destroyed absolute monarchy in France and forced the rest of Europe to "
            "confront new claims about citizenship, rights, and sovereignty. It was not a single event. "
            "These notes track fiscal crisis, political phases, and the revolution's contradictory outcomes."
        ),
        terms=[
            ("Ancien régime", "The pre-1789 social and political order of estates and royal absolutism."),
            ("Estates-General", "Assembly of clergy, nobility, and Third Estate called in 1789 to address the fiscal crisis."),
            ("Jacobins", "Radical political club that dominated the most militant phase of the revolution."),
            ("Napoleon Bonaparte", "General who ended the Directory and built an authoritarian state that exported some revolutionary reforms."),
        ],
        explanations=[
            (
                "Fiscal and social origins",
                "War debts, a regressive tax system, and poor harvests collided in the 1780s. The First and "
                "Second Estates kept privileges while the Third Estate paid. Enlightenment arguments about "
                "natural rights gave critics a language. The calling of the Estates-General opened a political "
                "space the crown could not close.",
            ),
            (
                "Phases",
                "1789–1791: National Assembly, Declaration of the Rights of Man, constitutional monarchy. "
                "1792–1794: republic, war, and the Terror under the Committee of Public Safety. 1795–1799: "
                "Directory, corruption, and military dependence. Each phase answered the previous phase's "
                "failures and created new enemies.",
            ),
            (
                "Wider impact",
                "The revolution abolished feudal dues, challenged established churches, and spread the idea "
                "that nations could remake themselves. It also produced mass conscription, political violence, "
                "and a template for later revolutions. Conservative Europe organized against it; colonial "
                "societies, notably Saint-Domingue, seized the language of rights for their own ends.",
            ),
        ],
        bullets=[
            "1789: Bastille, August decrees, Declaration of the Rights of Man.",
            "1791 constitution tried to keep the king inside a limited monarchy.",
            "1793–94 Terror: emergency government, price controls, executions.",
            "1799: Brumaire coup brings Napoleon to power.",
        ],
        examples=[
            "The Haitian Revolution shows revolutionary language traveling beyond metropolitan France.",
            "The Civil Constitution of the Clergy split Catholics and politicized religion.",
        ],
        worked=[
            (
                "Ranking causes for an essay",
                "Prompt: Why did the French monarchy collapse in 1789?\n"
                "1. Separate long-term structures (estates, tax privilege) from short-term triggers (1788 harvest, bankruptcy).\n"
                "2. Give the fiscal crisis causal weight: without it, the Estates-General is not called.\n"
                "3. Treat ideas as accelerants, not a complete explanation by themselves.\n"
                "4. End with contingency: elite resistance to reform turned a budget crisis into a revolution.",
            ),
        ],
        pitfalls=[
            "The revolution did not instantly create a stable liberal democracy.",
            "Do not treat 'the people' as a single actor; sans-culottes, peasants, and bourgeois deputies wanted different things.",
        ],
        review=[
            "Why did calling the Estates-General backfire for Louis XVI?",
            "What problem was the Terror trying to solve, according to its leaders?",
            "Name one revolutionary change that Napoleon kept and one he reversed.",
        ],
    ),
    _topic(
        slug="industrial-revolution",
        title="The Industrial Revolution in Britain",
        overview=(
            "Industrialization shifted production from homes and workshops to factories powered first by "
            "water and then by coal and steam. Britain was first, which is why exam questions often start "
            "there. These notes cover energy, labor, cities, and the political fights that followed."
        ),
        terms=[
            ("Cottage industry", "Household production, often textiles, before concentrated factories."),
            ("Steam engine", "Heat engine, improved by Watt, that freed industry from riverside mill sites."),
            ("Urbanization", "Growth of cities as workers moved toward factories and ports."),
            ("Luddites", "Workers who smashed machines they saw as threats to skilled livelihoods."),
        ],
        explanations=[
            (
                "Why Britain first",
                "Commercial agriculture, colonial markets, accessible coal, navigable rivers, and relatively "
                "secure property rights all mattered. So did a culture of practical invention. No single cause "
                "suffices. Cotton textiles were the leading sector because mechanization there paid quickly.",
            ),
            (
                "Social consequences",
                "Factory time replaced task time. Child labor, long hours, and crowded housing were common. "
                "Real wages eventually rose, but the early decades were harsh for many. A new industrial "
                "middle class gained political ambition, while a working class began to organize.",
            ),
            (
                "Political responses",
                "Reform Acts expanded the franchise in stages. Factory Acts limited hours. Repeal of the Corn "
                "Laws in 1846 signaled a shift toward free trade. Chartism demanded political inclusion for "
                "working men. Industrial society produced both wealth and a new question: who should govern it?",
            ),
        ],
        bullets=[
            "Coal + steam + iron formed a feedback loop.",
            "Railways cut transport costs and integrated markets.",
            "Public health lagged urban growth; cholera epidemics followed.",
            "Industrialization spread later to Belgium, France, Germany, the United States, and Japan.",
        ],
        examples=[
            "Manchester became a symbol of cotton mills, soot, and new class relations.",
            "The 1833 Factory Act inspected mills and restricted child labor, imperfectly.",
        ],
        worked=[
            (
                "Source analysis: a mill report",
                "A parliamentary inspector describes 12-hour days for children in 1832.\n"
                "1. Identify the source type: official inquiry, reformist purpose.\n"
                "2. Note what it can show (conditions claimed) and cannot (typical wages nationwide).\n"
                "3. Corroborate with a second source: a mill owner's testimony will likely stress discipline and wages.\n"
                "4. Thesis: industrial growth created wealth and a documented labor crisis at the same time.",
            ),
        ],
        pitfalls=[
            "Industrialization was regional, not evenly spread across all of Britain in 1800.",
            "Do not treat later Victorian living-standard gains as proof that 1790s factory life was comfortable.",
        ],
        review=[
            "Give two reasons Britain industrialized before France.",
            "How did steam change the geography of industry?",
            "What did Chartists want that the 1832 Reform Act did not deliver?",
        ],
    ),
    _topic(
        slug="cold-war",
        title="The Cold War, 1945–1991",
        overview=(
            "The Cold War was a global contest between the United States and the Soviet Union that stopped "
            "short of direct full-scale war between the two. It was fought with alliances, nuclear threats, "
            "proxy wars, espionage, and competing models of political economy. Periodization helps: origins, "
            "crises, detente, and the 1980s endgame."
        ),
        terms=[
            ("Containment", "U.S. strategy of blocking Soviet expansion rather than rolling it back immediately."),
            ("NATO", "U.S.-led military alliance formed in 1949."),
            ("Warsaw Pact", "Soviet-led alliance formed in 1955 in response to West German rearmament."),
            ("Detente", "Period of reduced tension and arms-control agreements, especially in the 1970s."),
        ],
        explanations=[
            (
                "Origins",
                "Wartime cooperation hid incompatible aims. The USSR wanted a security belt in Eastern Europe. "
                "The United States wanted open markets and self-determination as it defined them. Atomic weapons, "
                "the Truman Doctrine, the Marshall Plan, and the Berlin blockade turned suspicion into a system.",
            ),
            (
                "Crisis years",
                "Korea, the Hungarian uprising, the Berlin Wall, the Cuban Missile Crisis, and Vietnam show "
                "different faces of the conflict: limited war, suppressed revolt, symbolic division, nuclear "
                "brinkmanship, and a costly proxy war. The Cuban crisis is the closest the superpowers came "
                "to nuclear war, and it produced a lasting interest in hotlines and arms control.",
            ),
            (
                "End of the conflict",
                "Economic stagnation, the Afghan war, and nationalist pressure strained the Soviet system. "
                "Gorbachev's glasnost and perestroika were meant to reform socialism, not abolish it. "
                "Eastern European regimes fell in 1989; the Soviet Union dissolved in 1991. The end was rapid "
                "compared with the decades of stalemate that preceded it.",
            ),
        ],
        bullets=[
            "Bipolarity: two superpowers, many local actors with their own goals.",
            "Nuclear deterrence made direct war extremely risky.",
            "Decolonization turned Asia, Africa, and the Middle East into Cold War arenas.",
            "China split from Soviet tutelage and became a third pole after the 1960s.",
        ],
        examples=[
            "The Marshall Plan tied Western European recovery to U.S. markets and politics.",
            "Non-aligned leaders tried to avoid becoming client states.",
        ],
        worked=[
            (
                "Comparing interpretations",
                "Question: Who was more responsible for the Cold War's origins?\n"
                "1. Orthodox view: Soviet expansion forced a U.S. response.\n"
                "2. Revisionist view: U.S. economic and atomic power threatened Soviet security needs.\n"
                "3. Post-revisionist view: misperception plus structure; both sides contributed.\n"
                "A strong essay picks a weighted position and uses 1945–49 evidence, not later Vietnam.",
            ),
        ],
        pitfalls=[
            "The Cold War was not only Europe; Korea, Cuba, Angola, and Afghanistan are central.",
            "Do not treat 1991 as proof that containment was a simple, linear success from 1947 onward.",
        ],
        review=[
            "What did containment mean in practice in 1947–49?",
            "Why was the Cuban Missile Crisis a turning point?",
            "How did Gorbachev's reforms undermine Soviet control in Eastern Europe?",
        ],
    ),
    _topic(
        slug="roman-republic-empire",
        title="From Roman Republic to Empire",
        overview=(
            "Rome's republic was designed for a city-state and then stretched over a Mediterranean empire. "
            "That mismatch produced civil wars and, eventually, one-man rule under Augustus. These notes "
            "focus on institutions, the late-republican crisis, and what 'empire' changed."
        ),
        terms=[
            ("Senate", "Council of elite Romans that guided policy, especially in foreign affairs and finance."),
            ("Consul", "One of two annually elected chief magistrates of the republic."),
            ("Dictator", "Emergency magistrate with extraordinary power; later a label for men who seized power."),
            ("Principate", "Augustus's system: republican forms with monarchical substance."),
        ],
        explanations=[
            (
                "Republican checks",
                "Collegiality, short terms, and the veto were supposed to prevent monarchy. In practice, "
                "nobles competed for honor through war and patronage. As Rome conquered Italy and then the "
                "Mediterranean, generals gained armies more loyal to them than to the Senate.",
            ),
            (
                "The late republic",
                "Tiberius and Gaius Gracchus raised land and citizenship questions and were killed. Marius "
                "recruited landless soldiers. Sulla marched on Rome. Pompey, Crassus, and Caesar formed a "
                "private coalition. Caesar's assassination in 44 BCE did not restore the old republic; it "
                "opened another civil war.",
            ),
            (
                "Augustan settlement",
                "Octavian defeated Antony and Cleopatra, then presented himself as restorer of the republic "
                "while holding tribunician power, military command, and unmatched patronage. The empire "
                "brought longer peace in the core, a professional army, and imperial cult — at the cost of "
                "competitive elite politics in the old style.",
            ),
        ],
        bullets=[
            "Punic Wars made Rome a Mediterranean great power.",
            "Slave labor and latifundia transformed Italian agriculture.",
            "Citizenship expanded slowly; the Social War forced a leap.",
            "Succession remained the empire's chronic weakness.",
        ],
        examples=[
            "Caesar's Commentaries are both campaign record and political advertisement.",
            "The Praetorian Guard could make or unmake later emperors.",
        ],
        worked=[
            (
                "Was Augustus a republican or a monarch?",
                "1. List republican survivals: Senate, consuls, elections with reduced meaning.\n"
                "2. List monarchical realities: control of armies, provinces, and grain.\n"
                "3. Use Augustus's own Res Gestae cautiously; it is self-presentation.\n"
                "4. Conclusion: the principate was a monarchy wearing republican clothing.",
            ),
        ],
        pitfalls=[
            "The republic was oligarchic, not a modern democracy.",
            "Do not skip the century of civil war; the empire did not appear overnight in 27 BCE.",
        ],
        review=[
            "How did imperial expansion undermine republican institutions?",
            "What did the Gracchi attempt, and why did it matter?",
            "Name two tools Augustus used to make one-man rule acceptable.",
        ],
    ),
    _topic(
        slug="silk-roads",
        title="The Silk Roads and Cross-Cultural Exchange",
        overview=(
            "The Silk Roads were a network of overland and maritime routes linking East Asia, Central Asia, "
            "India, the Middle East, and the Mediterranean. Goods moved, but so did religions, technologies, "
            "and pathogens. These notes treat the routes as a system, not a single highway."
        ),
        terms=[
            ("Caravanserai", "Roadside inn that sheltered merchants and animals along overland routes."),
            ("Relay trade", "Goods changing hands many times rather than one merchant traveling the whole way."),
            ("Pax Mongolica", "Thirteenth-century period of relative security across much of Eurasia under Mongol rule."),
            ("Monsoon winds", "Seasonal winds that made Indian Ocean voyages predictable."),
        ],
        explanations=[
            (
                "What traveled",
                "Silk, spices, horses, glass, and precious metals are the famous cargoes. Equally important "
                "were paper, gunpowder knowledge, and crops. Buddhism moved from India into China along oasis "
                "towns. Islam later spread through merchants as well as armies. Exchange was selective: "
                "societies borrowed what fit local needs.",
            ),
            (
                "Risk and infrastructure",
                "Deserts, bandits, and political fragmentation made long-distance trade expensive. Empires "
                "that could tax and protect routes — Han, Kushan, Abbasid, Mongol — thickened exchange. When "
                "those empires fractured, trade did not vanish, but it rerouted toward the sea or shorter legs.",
            ),
            (
                "Disease and the limits of connection",
                "The same networks that carried silk could carry Yersinia pestis. The Black Death's fourteenth-"
                "century spread is a grim reminder that globalization is old. After the Mongol century, "
                "overland volume fell relative to maritime trade, but the idea of a connected Eurasia remained.",
            ),
        ],
        bullets=[
            "Oasis cities such as Samarkand were nodes, not just waypoints.",
            "Maritime silk routes often moved bulkier goods more cheaply.",
            "Sogdian merchants were famous intermediaries in earlier centuries.",
            "Demand in elite markets, not mass consumption, drove many luxury trades.",
        ],
        examples=[
            "Buddhist cave sites at Dunhuang preserve art shaped by passing pilgrims and patrons.",
            "Chinese knowledge of distillation and later gunpowder moved westward in stages.",
        ],
        worked=[
            (
                "Explaining a map in an essay",
                "You are given a map of eighth-century routes.\n"
                "1. Identify land versus sea legs and major empires that could tax them.\n"
                "2. Pick one luxury good and one idea (for example silk and Buddhism).\n"
                "3. Explain a friction: desert crossing, piracy, or a political border.\n"
                "4. Finish with a consequence: urban growth in a node city or religious change.",
            ),
        ],
        pitfalls=[
            "There was no single 'Silk Road' with one start and end date.",
            "Most people never traveled these routes; connection was real but socially narrow.",
        ],
        review=[
            "Why do historians prefer 'Silk Roads' in the plural?",
            "How did the Mongol Empire temporarily lower transaction costs?",
            "Give one example of a religion spreading through trade rather than conquest.",
        ],
    ),
    _topic(
        slug="decolonization-africa",
        title="Decolonization in Africa after 1945",
        overview=(
            "Between the 1950s and 1970s most African colonies became independent states. The process was "
            "uneven: negotiated transfers in some places, long wars in others. These notes emphasize "
            "causes, different paths, and the constraints new states inherited."
        ),
        terms=[
            ("Nationalism", "Political claim that a people should govern themselves as a sovereign state."),
            ("Settler colony", "Colony with a substantial European population claiming permanent belonging, often resisting majority rule."),
            ("Neocolonialism", "Argument that formal independence left economic and political dependence intact."),
            ("Organization of African Unity", "1963 body that generally accepted colonial borders to limit interstate war."),
        ],
        explanations=[
            (
                "Why empires retreated",
                "World War II weakened European powers and discredited racial hierarchies. The UN provided a "
                "forum for anti-colonial claims. Superpowers competed for influence and rarely wanted to fund "
                "old empires. African parties, unions, veterans, and students organized. Independence was won, "
                "not merely granted, even where the final ceremony looked peaceful.",
            ),
            (
                "Divergent paths",
                "Ghana (1957) became a model of relatively negotiated British transfer. Algeria's war against "
                "France (1954–62) was brutal because a large settler population and the idea of Algeria as "
                "part of France blocked compromise. Portuguese colonies fought into the 1970s. Southern Africa's "
                "white-minority regimes lasted longer still.",
            ),
            (
                "After independence",
                "New states inherited colonial borders, thin administrations, and export-oriented economies. "
                "Leaders faced the task of building nations from diverse societies. Some pursued African "
                "socialism or one-party systems they justified as unity. Cold War patronage shaped choices. "
                "Success and failure varied widely; avoid a single 'Africa' story.",
            ),
        ],
        bullets=[
            "1950s–60s: most of British and French tropical Africa becomes independent.",
            "1960 is often called the Year of Africa at the UN.",
            "Borders mostly followed colonial lines (uti possidetis).",
            "Economic structures often still favored old metropolitan firms and cash crops.",
        ],
        examples=[
            "Kwame Nkrumah's Ghana linked independence to pan-African ambition.",
            "The Algerian War transformed French politics as well as Algerian society.",
        ],
        worked=[
            (
                "Comparing two cases",
                "Task: contrast Ghana and Algeria.\n"
                "1. Colony type: tropical British colony versus French settler colony.\n"
                "2. Method: elections and negotiation versus guerrilla war and mass displacement.\n"
                "3. Metropolitan politics: Britain accepted transfer earlier; France fought to keep Algeria.\n"
                "4. Point: the presence of settlers and the legal status of the colony changed the violence of exit.",
            ),
        ],
        pitfalls=[
            "Independence dates are not the whole story; economic and military ties often continued.",
            "Do not treat colonial rule as uniformly 'weak' or uniformly 'total'; it varied by region and decade.",
        ],
        review=[
            "Name two global and two local causes of decolonization.",
            "Why were settler colonies harder to decolonize peacefully?",
            "What problem did keeping colonial borders try to prevent?",
        ],
    ),
    _topic(
        slug="scientific-revolution",
        title="The Scientific Revolution",
        overview=(
            "Between the sixteenth and eighteenth centuries, a cluster of European thinkers changed how "
            "nature was described and who had authority to describe it. The change was uneven and still "
            "debated. These notes cover astronomy, method, institutions, and limits of the 'revolution' label."
        ),
        terms=[
            ("Heliocentrism", "Model placing the Sun, not the Earth, at the center of the known planetary system."),
            ("Empiricism", "Emphasis on observation and experiment as sources of knowledge."),
            ("Mechanical philosophy", "View of nature as matter in motion, often contrasted with older teleology."),
            ("Royal Society", "English institution (1660) for sharing experiments and papers."),
        ],
        explanations=[
            (
                "Astronomy as the spearhead",
                "Copernicus proposed a heliocentric model. Kepler replaced circular orbits with ellipses. "
                "Galileo's telescope observations undermined crystal spheres. Newton unified celestial and "
                "terrestrial motion with universal gravitation. Each step was contested, and older Aristotelian "
                "physics did not vanish overnight.",
            ),
            (
                "Method and print",
                "Bacon advertised collective, experimental inquiry. Descartes sought certain foundations through "
                "reason. In practice, science mixed instruments, mathematics, patronage, and correspondence "
                "networks. Print and letters let results travel; priority disputes show how reputation mattered.",
            ),
            (
                "Society and limits",
                "Universities, courts, and new academies sponsored work. Women and artisans contributed more "
                "than older textbooks admitted, often without institutional credit. The Scientific Revolution "
                "was largely a European story in its classic telling, but it drew on earlier Islamic, Indian, "
                "and Chinese knowledge and on data from global voyages.",
            ),
        ],
        bullets=[
            "Instruments: telescope, microscope, air pump, pendulum clock.",
            "Newton's Principia (1687) became a model of mathematical physics.",
            "Conflict with churches was real in some cases, overstated in others.",
            "Natural knowledge was still mixed with alchemy and astrology for many practitioners.",
        ],
        examples=[
            "Galileo's trial is a specific political-religious event, not a summary of all science-religion relations.",
            "Newton's work on optics sat beside his alchemical notebooks.",
        ],
        worked=[
            (
                "Evaluating the word 'revolution'",
                "1. Continuity: universities still taught Aristotle for a long time.\n"
                "2. Rupture: predictive mathematical physics and new institutions.\n"
                "3. Geography: the standard narrative is Europe-centered and incomplete.\n"
                "4. Verdict to defend: a real transformation in authority and method, stretched over two centuries, not a single break in 1543.",
            ),
        ],
        pitfalls=[
            "Do not reduce the period to 'science versus religion' as a cartoon.",
            "Copernicus did not 'prove' heliocentrism by himself; evidence accumulated after him.",
        ],
        review=[
            "What problem did Kepler solve that Copernicus left in place?",
            "Why do institutions such as the Royal Society matter to this story?",
            "Give one reason historians argue about the label 'Scientific Revolution'.",
        ],
    ),
    _topic(
        slug="civil-rights-us",
        title="The U.S. Civil Rights Movement, 1954–1968",
        overview=(
            "The African American freedom struggle of the 1950s and 1960s attacked legal segregation and "
            "disenfranchisement in the United States. It drew on older organizing and produced landmark "
            "federal laws. These notes cover legal strategy, mass protest, and unfinished economic goals."
        ),
        terms=[
            ("Jim Crow", "System of state and local laws enforcing racial segregation, especially in the South."),
            ("Nonviolent direct action", "Tactics such as sit-ins and marches designed to expose injustice without armed revolt."),
            ("SNCC", "Student Nonviolent Coordinating Committee, a student-led organization central to sit-ins and Freedom Summer."),
            ("Voting Rights Act", "1965 federal law targeting discriminatory voting practices."),
        ],
        explanations=[
            (
                "Legal opening",
                "Brown v. Board of Education (1954) declared segregated public schools unconstitutional. "
                "Implementation was slow and fiercely resisted. The decision still mattered: it undercut the "
                "legal logic of Plessy and encouraged further litigation and protest. Courts, however, could "
                "not register voters or desegregate lunch counters by themselves.",
            ),
            (
                "Mass movement",
                "Montgomery's bus boycott, sit-ins, Freedom Rides, Birmingham, and the March on Washington "
                "combined local leadership with national media. Churches, students, and Black legal organizations "
                "were infrastructure. White supremacist violence was not incidental; it was a strategy, and "
                "televised brutality shifted some Northern opinion.",
            ),
            (
                "Laws and limits",
                "The Civil Rights Act (1964) and Voting Rights Act (1965) were historic. They did not end "
                "poverty, police violence, or de facto segregation in housing and schools. After 1965, debates "
                "over Black Power, Vietnam, and economic justice fractured coalitions that had focused on "
                "legal equality in the South.",
            ),
        ],
        bullets=[
            "Local people, not only famous national leaders, built campaigns.",
            "Federal action often followed crisis, not moral conversion alone.",
            "Women organized extensively and were often sidelined in public leadership narratives.",
            "The movement had Northern targets too: housing, jobs, and schools.",
        ],
        examples=[
            "Freedom Summer (1964) brought voter registration and a challenge to Mississippi's segregated delegation.",
            "The Selma campaign made the voting-rights case visible in 1965.",
        ],
        worked=[
            (
                "Causation in 1964–65",
                "Prompt: Why did Congress pass the Voting Rights Act?\n"
                "1. Long-term: disenfranchisement tools (literacy tests, violence, poll taxes in earlier form).\n"
                "2. Movement pressure: Selma, SNCC, SCLC, local marchers.\n"
                "3. Presidential calculation: Johnson's coalition and the shock of televised violence.\n"
                "4. Do not stop at 'LBJ passed it'; statutes followed organized risk-taking.",
            ),
        ],
        pitfalls=[
            "The movement did not begin in 1954 or end in 1968.",
            "Avoid a story that has only Martin Luther King Jr. as the actor.",
        ],
        review=[
            "What did Brown decide, and what did it not immediately accomplish?",
            "How did nonviolent direct action work as a strategy?",
            "Why did voting rights require a separate statute after 1964?",
        ],
    ),
]

NETWORKING: list[Topic] = [
    _topic(
        slug="osi-model",
        title="The OSI Model and Real Protocol Stacks",
        overview=(
            "The OSI model is a seven-layer teaching framework for describing network functions. Real "
            "internet traffic usually runs on TCP/IP, which does not map one-to-one onto OSI. These notes "
            "use OSI as a vocabulary, then show where packets actually live."
        ),
        terms=[
            ("PDU", "Protocol data unit: the named chunk at a layer (frame, packet, segment, and so on)."),
            ("Encapsulation", "Wrapping higher-layer data with the current layer's header (and sometimes trailer)."),
            ("TCP/IP model", "Practical internet stack: link, internet, transport, application."),
            ("Peer layer", "The matching layer on the remote host that interprets a given header."),
        ],
        explanations=[
            (
                "The seven layers",
                "Physical: bits on a medium. Data link: framing and local delivery (Ethernet, Wi-Fi). Network: "
                "logical addressing and routing (IP). Transport: process-to-process channels (TCP, UDP). "
                "Session, presentation, and application are often collapsed in real stacks; TLS, HTTP, and DNS "
                "sit in that upper space depending on how strictly you apply OSI.",
            ),
            (
                "Encapsulation on the wire",
                "A browser HTTP request becomes a TCP segment inside an IP packet inside an Ethernet frame. "
                "Each hop that is a router strips the link header, inspects the IP header, and builds a new "
                "link header for the next hop. Switches generally do not inspect IP; they forward on MAC addresses.",
            ),
            (
                "Why the model still helps",
                "Troubleshooting is faster if you ask which layer failed. No link lights is physical. Wrong VLAN "
                "is data link. Ping fails by IP but ARP works is often network. A SYN with no SYN-ACK is "
                "transport or a filter. A TLS certificate error is above TCP. OSI is a checklist, not a religion.",
            ),
        ],
        bullets=[
            "L1 physical, L2 data link, L3 network, L4 transport, L5–L7 upper layers.",
            "IP is L3; TCP/UDP are L4; Ethernet is L2.",
            "ARP sits beside IPv4 at the link/internet boundary.",
            "Middleboxes (NAT, firewalls) break the clean end-to-end story.",
        ],
        examples=[
            "A ping test checks L3 reachability, not whether HTTPS will work.",
            "Wireshark shows headers from multiple layers in one capture.",
        ],
        worked=[
            (
                "Placing a failure",
                "Symptom: you can ping 8.8.8.8 but https://example.com fails in the browser.\n"
                "1. L3 to a public IP works, so routing and basic ICMP are not totally dead.\n"
                "2. Next: DNS. If the name does not resolve, the problem is application-layer naming.\n"
                "3. If DNS works, test TCP/443. A blocked port is a transport or firewall issue.\n"
                "4. If TCP works but TLS fails, inspect certificates and time.\n"
                "This is layer-oriented isolation, not guess-and-reboot.",
            ),
        ],
        pitfalls=[
            "OSI session and presentation layers rarely appear as standalone protocols on the internet.",
            "Do not say 'Layer 8' on an exam unless the question is joking; stick to the seven layers.",
        ],
        review=[
            "Which layer adds a MAC header?",
            "Why can a router rewrite L2 headers without changing the TCP payload?",
            "Map HTTP, TCP, IP, and Ethernet to layers.",
        ],
    ),
    _topic(
        slug="subnetting-cidr",
        title="IPv4 Subnetting and CIDR",
        overview=(
            "Subnetting splits an address block into smaller networks. CIDR replaced classful addressing so "
            "prefixes can be any length. You need to convert prefixes to masks, count hosts, and judge whether "
            "two addresses are in the same subnet. These notes emphasize method over memorizing class tables."
        ),
        terms=[
            ("Prefix length", "The number of leading bits that identify the network, written as /n."),
            ("Subnet mask", "32-bit mask with 1s in the network portion; 255.255.255.0 is /24."),
            ("Network address", "Address with host bits set to 0; identifies the subnet itself."),
            ("Broadcast address", "IPv4 address with host bits set to 1; used to reach all hosts on the subnet."),
        ],
        explanations=[
            (
                "From classes to CIDR",
                "Class A/B/C wasted space and made routing tables huge. CIDR lets a provider announce "
                "172.16.0.0/12 or a site use 10.0.0.0/23. The prefix is what routers match. Longer prefixes "
                "are more specific and win when two routes overlap.",
            ),
            (
                "Host math",
                "For prefix /n, there are 32−n host bits. The number of addresses is 2^(32−n). Usable hosts "
                "on a typical IPv4 subnet are that number minus network and broadcast, except on point-to-point "
                "links that may use /31. A /24 has 256 addresses and usually 254 usable hosts.",
            ),
            (
                "Design tradeoffs",
                "Smaller subnets limit broadcast domains and match security zones. They also consume more "
                "routing entries if you do not summarize. VLSM means using different prefix lengths in the "
                "same organization: /30 for a link, /24 for a user VLAN, /28 for a small server bay.",
            ),
        ],
        bullets=[
            "/8 = 255.0.0.0, /16 = 255.255.0.0, /24 = 255.255.255.0.",
            "Bitwise AND of address and mask yields the network address.",
            "Two hosts communicate directly at L3 only if they share the same prefix on that link.",
            "Default gateway must be in the same subnet as the host.",
        ],
        examples=[
            "10.8.4.17/22 is in 10.8.4.0/22, not in 10.8.4.0/24.",
            "A point-to-point WAN link often uses /30 (two usable) or /31.",
        ],
        worked=[
            (
                "Find network and broadcast",
                "Address: 192.168.10.70/26.\n"
                "1. /26 means mask 255.255.255.192. Block size in the last octet is 64.\n"
                "2. Subnets: 0, 64, 128, 192. 70 falls in 64–127.\n"
                "3. Network: 192.168.10.64. Broadcast: 192.168.10.127.\n"
                "4. Usable: 192.168.10.65–126. 192.168.10.70 is a valid host.",
            ),
        ],
        pitfalls=[
            "A /24 is not always 'a Class C'. CIDR dropped that requirement.",
            "Off-by-one errors on usable hosts are common: 2^h minus 2, except special cases.",
        ],
        review=[
            "How many usable hosts in a /27 on a standard LAN?",
            "Why must a default gateway share the host's subnet?",
            "What does a longer prefix mean for route selection?",
        ],
    ),
    _topic(
        slug="tcp-vs-udp",
        title="TCP versus UDP",
        overview=(
            "Transport protocols deliver data to the correct process using port numbers. TCP is a reliable "
            "byte stream; UDP is an unreliable datagram service. Choosing between them is an application "
            "design decision, not a moral ranking. These notes cover handshake, reliability, and when UDP wins."
        ),
        terms=[
            ("Port", "16-bit transport identifier that demultiplexs connections or datagrams on a host."),
            ("Three-way handshake", "TCP SYN, SYN-ACK, ACK sequence that establishes a connection."),
            ("Flow control", "Receiver advertised window that keeps a sender from overflowing buffers."),
            ("Congestion control", "Sender behavior that reacts to network loss or delay to protect the path."),
        ],
        explanations=[
            (
                "What TCP guarantees",
                "TCP offers ordered, duplicate-free delivery of a byte stream, retransmission of lost data, "
                "and congestion control. It is connection-oriented: state exists at both ends. That state has "
                "a cost (memory, handshake latency) and a benefit (the application can pretend the network is "
                "a pipe).",
            ),
            (
                "What UDP offers",
                "UDP adds ports and a checksum, then stops. No handshake, no retransmission, no ordering. "
                "DNS queries, real-time audio, and some tunnels want that minimalism. If reliability is needed, "
                "the application must provide it — QUIC does this over UDP on purpose, to control handshake "
                "and loss recovery in user space.",
            ),
            (
                "Failure modes",
                "TCP can stall on loss (head-of-line blocking in a single stream). UDP can drop a packet and "
                "the rest still play. Firewalls often allow outbound TCP 443 more readily than arbitrary UDP, "
                "which is why so many applications sit on HTTPS. NAT mapping lifetimes also differ.",
            ),
        ],
        bullets=[
            "TCP: connection, reliability, congestion control, higher overhead.",
            "UDP: connectionless, low overhead, application-defined reliability.",
            "Well-known ports: 80, 443 TCP; 53 UDP (and TCP for large DNS).",
            "A socket is typically {local IP, local port, remote IP, remote port, protocol}.",
        ],
        examples=[
            "A video call may use UDP so a late packet can be discarded instead of stalling the stream.",
            "File transfer prefers TCP (or QUIC) because missing bytes corrupt the file.",
        ],
        worked=[
            (
                "Handshake timing",
                "RTT is 80 ms. Ignore processing time.\n"
                "1. TCP connection setup needs one full RTT (SYN, SYN-ACK) before the client can send data "
                "in the completing ACK, or 1.5 RTT if data waits for the handshake to finish, depending on options.\n"
                "2. Classic TCP: client cannot send application data until the handshake completes ≈ 80 ms extra.\n"
                "3. UDP can send the request immediately.\n"
                "4. For a tiny DNS lookup, UDP's savings matter; for a 2 GB download, they do not.",
            ),
        ],
        pitfalls=[
            "TCP 'reliability' does not mean the path cannot fail; it means loss is repaired or the connection dies.",
            "UDP is not 'faster' in bandwidth; it can be lower-latency because it skips recovery.",
        ],
        review=[
            "List three TCP features UDP lacks.",
            "Why does DNS still use UDP for most queries?",
            "What problem does head-of-line blocking describe?",
        ],
    ),
    _topic(
        slug="dns-resolution",
        title="DNS Resolution",
        overview=(
            "DNS maps names to data, most famously A and AAAA records to addresses. Resolution is recursive "
            "from the stub resolver's point of view and iterative from a recursive resolver walking the "
            "hierarchy. These notes follow a query from browser cache to authoritative server."
        ),
        terms=[
            ("Stub resolver", "The client library on a host that asks a recursive resolver."),
            ("Recursive resolver", "Server that finds the answer on the client's behalf, using caches and referrals."),
            ("Authoritative server", "Server that holds the actual zone data for a name."),
            ("TTL", "Time to live: how long a record may be cached."),
        ],
        explanations=[
            (
                "The hierarchy",
                "A query for www.example.com checks local cache, then the configured resolver. If needed, that "
                "resolver asks a root, gets a referral to the .com TLD, then a referral to example.com's "
                "name servers, then an answer. Caching at each step is why the internet does not query the "
                "roots for every page load.",
            ),
            (
                "Record types",
                "A (IPv4), AAAA (IPv6), CNAME (alias), MX (mail), NS (delegated name servers), TXT (arbitrary "
                "text, often used for SPF and verification). CNAMEs cannot sit at the zone apex in classic "
                "DNS, which is why apex aliases need special provider features.",
            ),
            (
                "Failures and security",
                "NXDOMAIN means the name does not exist. SERVFAIL is an upstream or validation problem. "
                "DNSSEC signs records so a resolver can detect tampering. DoH and DoT encrypt the stub-to-"
                "resolver path. DNS remains a common outage source: a bad TTL or a missed record update can "
                "look like 'the internet is down'.",
            ),
        ],
        bullets=[
            "Resolution order: app cache → OS cache → recursive resolver → hierarchy.",
            "Glue records help find name servers that live inside the zone they serve.",
            "Split-horizon DNS can answer differently inside a company than outside.",
            "Port 53/UDP is common; TCP is used for large responses and zone transfers.",
        ],
        examples=[
            "Changing an A record may appear delayed until TTLs expire worldwide.",
            "A missing reverse PTR is not required for web browsing but matters for some mail servers.",
        ],
        worked=[
            (
                "Tracing www.example.com",
                "1. Stub asks 1.1.1.1 for A www.example.com.\n"
                "2. Resolver has no cache: query a root, receive NS for com.\n"
                "3. Query a com TLD server, receive NS for example.com plus glue.\n"
                "4. Query ns1.example.com, receive A 93.184.216.34 and TTL 86400.\n"
                "5. Resolver caches and returns the address to the stub.",
            ),
        ],
        pitfalls=[
            "Flushing your local cache does not flush the recursive resolver's cache.",
            "CNAME pointing at another CNAME works but adds latency and fragility.",
        ],
        review=[
            "Contrast recursive and iterative queries.",
            "What does a TTL of 60 seconds imply for a cutover?",
            "Why might a site work by IP but fail by name?",
        ],
    ),
    _topic(
        slug="routing-ospf-bgp",
        title="Routing Protocols: OSPF and BGP",
        overview=(
            "Hosts use a default gateway. Routers must learn how to reach prefixes they do not own. IGP "
            "protocols such as OSPF share topology inside an organization. BGP shares reachability between "
            "organizations and is the protocol of the internet's default-free zone. These notes keep the "
            "jobs distinct."
        ),
        terms=[
            ("IGP", "Interior gateway protocol used inside an autonomous system (OSPF, IS-IS, EIGRP)."),
            ("EGP", "Exterior protocol between autonomous systems; in practice, BGP."),
            ("AS", "Autonomous system: a network or set of networks under one routing policy."),
            ("Administrative distance", "Vendor-specific preference among sources of routes on one router."),
        ],
        explanations=[
            (
                "OSPF in brief",
                "OSPF is a link-state IGP. Routers flood LSAs, each builds the same topology map, and Dijkstra "
                "computes a shortest-path tree. Areas limit flood scope. Cost is typically derived from "
                "bandwidth. OSPF converges quickly on well-designed networks and is not meant to carry the "
                "whole internet table.",
            ),
            (
                "BGP in brief",
                "BGP is a path-vector protocol. It advertises prefixes with attributes, especially AS_PATH. "
                "Policy beats raw hop count: local preference, AS path length, MED, and more. iBGP and eBGP "
                "differ by whether the neighbor is in the same AS. A mis-originated prefix can blackhole "
                "traffic globally; that is why RPKI and filtering matter.",
            ),
            (
                "How they work together",
                "An enterprise may run OSPF internally and BGP to ISPs. The border router redistributes or "
                "originates a summary into BGP. You generally should not redistribute full BGP into OSPF. "
                "The design rule is: IGP for topology you control, BGP for policy at the edge.",
            ),
        ],
        bullets=[
            "OSPF neighbors form on links; BGP neighbors are explicitly configured.",
            "Longest prefix match still decides forwarding after the table is built.",
            "A default route (0.0.0.0/0) is how stubs reach the rest of the world.",
            "Route flaps and missing filters are operational hazards, not trivia.",
        ],
        examples=[
            "A company with two ISPs uses BGP to prefer one path and fail over to the other.",
            "An OSPF cost tweak can move traffic off a saturated core link.",
        ],
        worked=[
            (
                "Choosing a path",
                "Router has 10.0.0.0/16 via OSPF (cost 20) and 10.0.1.0/24 via a static route.\n"
                "Packet destination: 10.0.1.50.\n"
                "1. Longest match wins: /24 is more specific than /16.\n"
                "2. The static /24 is used, regardless of OSPF cost on the summary.\n"
                "3. If the static is withdrawn, OSPF /16 becomes the match.\n"
                "Specificity first, then preference among equal-length prefixes.",
            ),
        ],
        pitfalls=[
            "BGP is not 'faster OSPF for the internet'; it optimizes policy and scale.",
            "Two OSPF routers can be adjacent yet fail to share routes if areas or network types mismatch.",
        ],
        review=[
            "What problem do OSPF areas solve?",
            "Why is AS_PATH a loop-prevention tool?",
            "When would you originate a default route into OSPF?",
        ],
    ),
    _topic(
        slug="nat-and-pat",
        title="NAT and Port Address Translation",
        overview=(
            "Network Address Translation rewrites IP addresses as packets cross a boundary. The common home "
            "and enterprise form is NAPT (often called PAT): many private hosts share one public IPv4 address "
            "by translating ports. NAT extended IPv4's life and complicated end-to-end connectivity."
        ),
        terms=[
            ("RFC 1918", "Private IPv4 ranges: 10/8, 172.16/12, 192.168/16."),
            ("PAT / NAPT", "Many-to-one translation using transport ports."),
            ("STUN", "Protocol that helps applications discover their external mapped address."),
            ("Hairpinning", "NAT behavior when two internal hosts communicate using each other's public mapping."),
        ],
        explanations=[
            (
                "Why NAT spread",
                "IPv4 exhaustion made public addresses scarce. NAT lets a site use private space internally "
                "and a handful of public addresses at the edge. It also hides internal topology, which some "
                "treat as a security bonus. It is not a firewall by itself: without filtering, translated "
                "packets still flow.",
            ),
            (
                "What breaks",
                "Inbound connections need a mapping in advance (port forwarding) or an application-level "
                "gateway. Protocols that embed IP addresses in payloads (older SIP, FTP active mode) need "
                "helpers. End-to-end IPsec is awkward. Carrier-grade NAT makes even more applications need "
                "traversal tricks.",
            ),
            (
                "IPv6 and the future",
                "IPv6 restores globally unique addresses and can remove NAT as a scarcity tool. In practice, "
                "many networks still NAT IPv4 while running IPv6 in parallel. Understanding NAT remains "
                "required because the installed base is enormous.",
            ),
        ],
        bullets=[
            "Typical home router: private LAN + PAT to one WAN IPv4.",
            "Mappings time out; long-idle UDP flows die first on many devices.",
            "Static NAT is one-to-one; PAT is many-to-one.",
            "CGNAT shares public IPv4 among many subscribers.",
        ],
        examples=[
            "Hosting a game server at home requires a port-forward to the internal host.",
            "Two phones on the same LTE CGNAT may fail P2P until a relay is used.",
        ],
        worked=[
            (
                "Reading a translation table",
                "Inside host 192.168.1.20:53122 talks to 93.184.216.34:443.\n"
                "WAN address 203.0.113.8.\n"
                "1. Outbound packet source becomes 203.0.113.8:40000 (example mapped port).\n"
                "2. Return packets to 203.0.113.8:40000 rewrite dest to 192.168.1.20:53122.\n"
                "3. A second host 192.168.1.21 uses a different mapped port on the same WAN IP.\n"
                "Ports are what make sharing one IPv4 possible.",
            ),
        ],
        pitfalls=[
            "NAT is not encryption and not authentication.",
            "Assuming you can accept inbound TCP without a mapping is the usual surprise.",
        ],
        review=[
            "Name the three RFC 1918 blocks.",
            "Why does PAT need a port in the mapping?",
            "Give one application behavior that NAT complicates.",
        ],
    ),
    _topic(
        slug="tls-https",
        title="TLS and HTTPS",
        overview=(
            "HTTPS is HTTP over a TLS-protected stream. TLS provides confidentiality, integrity, and server "
            "authentication (and optionally client authentication). These notes follow a typical TLS 1.3 "
            "handshake at a level useful for operators, not cryptographers."
        ),
        terms=[
            ("Certificate", "Signed document binding a public key to a name, issued by a CA."),
            ("SNI", "Server Name Indication: the client tells which hostname it wants during the handshake."),
            ("Forward secrecy", "Property that stolen long-term keys cannot decrypt past recorded sessions."),
            ("HSTS", "HTTP header that forces browsers to use HTTPS on later visits."),
        ],
        explanations=[
            (
                "What TLS does not do",
                "TLS authenticates the server to the client if the certificate chain validates and the name "
                "matches. It does not by itself authenticate the user. It does not stop XSS or a compromised "
                "web app. It also does not hide the destination IP or, in older TLS, the SNI hostname.",
            ),
            (
                "Certificates in practice",
                "A CA signs a leaf certificate. Browsers trust a set of roots. Let's Encrypt automated issuance "
                "and made HTTPS default. Operators must watch expiry, name coverage (SAN list), and whether "
                "the private key is stored safely. A mismatch between the URL host and the certificate name "
                "is the classic browser error.",
            ),
            (
                "Operational checks",
                "Test from outside the network: intercepting proxies can hide problems. Verify redirect from "
                "HTTP to HTTPS, OCSP/CRL behavior, and TLS versions offered. Disable ancient protocols. "
                "Mixed content (HTTPS page loading HTTP scripts) undermines the lock icon.",
            ),
        ],
        bullets=[
            "TCP handshake first, then TLS, then HTTP — unless using QUIC, which combines transport and TLS.",
            "TLS 1.3 cuts handshake round trips versus 1.2.",
            "Certificates expire; automation is safer than calendars.",
            "Certificate pinning is rare on the public web; CT logs add transparency.",
        ],
        examples=[
            "A load balancer may terminate TLS and forward plain HTTP internally — a design you should document.",
            "Missing SNI on a client can hit the default certificate on a shared IP.",
        ],
        worked=[
            (
                "Debugging a name mismatch",
                "User opens https://shop.example.com and the browser warns.\n"
                "1. Inspect the certificate CN/SAN: it lists only www.example.com.\n"
                "2. DNS for shop.example.com points at the same VIP.\n"
                "3. Fix: issue a certificate that includes shop.example.com, or redirect to the listed name.\n"
                "4. Confirm after deploy with a fresh connection, not a cached interstitial.",
            ),
        ],
        pitfalls=[
            "A green lock never meant 'this shop is honest'; it means the channel is authenticated to some name.",
            "Self-signed certificates are fine for labs, not for public users.",
        ],
        review=[
            "What three security properties is TLS aiming for?",
            "Why is SNI needed on shared hosting?",
            "How does TLS 1.3 improve on 1.2 at a high level?",
        ],
    ),
    _topic(
        slug="switching-vlans",
        title="Ethernet Switching and VLANs",
        overview=(
            "Switches forward Ethernet frames using MAC address tables. VLANs split one physical fabric into "
            "multiple broadcast domains. Almost every campus network depends on this pair of ideas. These "
            "notes cover learning, flooding, trunks, and loops."
        ),
        terms=[
            ("MAC address table", "Switch mapping from MAC address to port (and VLAN)."),
            ("VLAN", "Logical broadcast domain on a switched network."),
            ("Trunk", "Link that carries multiple VLANs, usually with 802.1Q tags."),
            ("STP", "Spanning Tree Protocol, which blocks redundant links to prevent loops."),
        ],
        explanations=[
            (
                "How a switch forwards",
                "On an unknown unicast, a switch floods within the VLAN. When a reply arrives, it learns the "
                "source MAC and later ports only to the correct port. Broadcasts and some multicasts still "
                "flood. That is why oversized L2 domains hurt: one ARP storm reaches everyone.",
            ),
            (
                "VLANs and trunks",
                "Access ports belong to one VLAN. Trunks tag frames so the far switch knows the VLAN. Native "
                "VLAN is the untagged VLAN on a trunk and a common misconfiguration source. Inter-VLAN routing "
                "needs a Layer 3 device: a router-on-a-stick or a Layer 3 switch SVI.",
            ),
            (
                "Loops",
                "Ethernet has no TTL. A loop without STP multiplies broadcasts until the LAN melts. STP elects "
                "a root and blocks ports. Faster variants (RSTP) converge in seconds. Modern designs also use "
                "link aggregation and sometimes overlay fabrics, but the exam still expects STP literacy.",
            ),
        ],
        bullets=[
            "Same VLAN + same subnet is the usual design pairing.",
            "Different VLANs cannot talk without L3 routing.",
            "CAM table timeout is often five minutes; silent hosts may be flooded again.",
            "Port security can limit MACs on an access port.",
        ],
        examples=[
            "Voice VLAN: a phone tags voice frames and passes untagged data from a PC.",
            "A forgotten native VLAN mismatch drops control traffic and is painful to spot.",
        ],
        worked=[
            (
                "Why can't VLAN 10 ping VLAN 20?",
                "PC A 10.10.10.8/24 VLAN 10, PC B 10.10.20.8/24 VLAN 20, same switch stack.\n"
                "1. They are different subnets, so A sends to its gateway, not to B's MAC.\n"
                "2. If no SVI or router exists, the gateway is missing and ping fails.\n"
                "3. Even with a router, ACLs might block.\n"
                "4. Fix path: confirm SVIs, default gateways, and then filters.",
            ),
        ],
        pitfalls=[
            "A VLAN is not a subnet, though they are usually mapped 1:1.",
            "Switching is not routing; MAC tables are not IP routing tables.",
        ],
        review=[
            "When does a switch flood a frame?",
            "What does an 802.1Q tag carry?",
            "Why is STP still relevant on a campus with redundant uplinks?",
        ],
    ),
]

ECONOMICS: list[Topic] = [
    _topic(
        slug="supply-demand",
        title="Supply, Demand, and Market Equilibrium",
        overview=(
            "Competitive markets coordinate through prices. Demand summarizes buyers' willingness to pay; "
            "supply summarizes sellers' willingness to produce. Equilibrium is the price where quantity "
            "demanded equals quantity supplied. These notes emphasize shifts versus movements along a curve."
        ),
        terms=[
            ("Demand curve", "Relationship between price and quantity demanded, holding other factors fixed."),
            ("Supply curve", "Relationship between price and quantity supplied, holding other factors fixed."),
            ("Equilibrium", "Price and quantity where the market clears."),
            ("Shortage", "Quantity demanded exceeds quantity supplied at the current price."),
        ],
        explanations=[
            (
                "Movements versus shifts",
                "A change in the good's own price moves you along the curve. A change in income, tastes, "
                "prices of related goods, or expectations shifts demand. Input costs, technology, and the "
                "number of sellers shift supply. Mixing these up is the most common graph error.",
            ),
            (
                "How equilibrium adjusts",
                "If price is too high, a surplus pushes it down. If too low, a shortage pushes it up. In a "
                "simple model this happens without a central planner. Real markets have frictions — menus, "
                "contracts, search — but the surplus/shortage logic is still the starting point.",
            ),
            (
                "Controls",
                "A binding price ceiling (rent control) sits below equilibrium and creates a shortage plus "
                "non-price rationing. A binding floor (some minimum wages in a simple model, agricultural "
                "price supports) creates a surplus. Whether those policies are desirable is a separate "
                "normative question; the positive prediction is about quantities.",
            ),
        ],
        bullets=[
            "Ceteris paribus: other things equal when drawing a single curve.",
            "Normal goods: income up, demand shifts right. Inferior goods: the opposite.",
            "Complements: price of A up, demand for B left. Substitutes: the reverse.",
            "Consumer surplus is area under demand and above price; producer surplus is above supply and below price.",
        ],
        examples=[
            "A popular concert with a low official price produces queues and scalping — a shortage.",
            "Better fertilizer shifts food supply right and tends to lower prices, other things equal.",
        ],
        worked=[
            (
                "Shift identification",
                "News: a freeze destroys orange groves. Orange juice market.\n"
                "1. Freeze is an input/supply shock, not a change in juice drinkers' incomes.\n"
                "2. Supply shifts left. Demand unchanged in the basic story.\n"
                "3. Equilibrium price rises; equilibrium quantity falls.\n"
                "4. The movement along the demand curve is the price increase, not a demand shift.",
            ),
        ],
        pitfalls=[
            "A price change does not shift the demand curve for that same good.",
            "Quantity demanded and demand are not synonyms.",
        ],
        review=[
            "What happens to equilibrium if demand rises and supply rises by more?",
            "Draw a binding ceiling and mark the shortage.",
            "Is a change in input prices a demand story or a supply story?",
        ],
    ),
    _topic(
        slug="price-elasticity",
        title="Price Elasticity of Demand",
        overview=(
            "Elasticity measures responsiveness. Price elasticity of demand is the percent change in quantity "
            "demanded divided by the percent change in price. Firms, tax authorities, and regulators all "
            "care because it tells you how much quantity (and revenue) will move."
        ),
        terms=[
            ("Elastic demand", "|Ed| > 1: quantity moves proportionally more than price."),
            ("Inelastic demand", "|Ed| < 1: quantity moves proportionally less than price."),
            ("Unit elastic", "|Ed| = 1: percent changes match."),
            ("Revenue", "Price times quantity; its change depends on elasticity."),
        ],
        explanations=[
            (
                "Determinants",
                "More substitutes, longer time to adjust, and a larger budget share tend to raise |Ed|. "
                "Narrowly defined goods (a brand of cereal) are more elastic than broad ones (food). "
                "Necessities are often inelastic in the short run. Always state the time horizon.",
            ),
            (
                "Midpoint method",
                "Using the average of old and new price and quantity avoids the problem that an increase "
                "and a decrease would otherwise give different elasticities. Exam problems often require "
                "that formula. Arc elasticity is the same idea.",
            ),
            (
                "Taxes and incidence",
                "The statutory payer of a tax is not always the economic payer. The more inelastic side of "
                "the market bears more of the tax. That is why cigarette taxes fall heavily on buyers if "
                "demand is inelastic, and why a tax on a perfectly elastic supply is borne by buyers.",
            ),
        ],
        bullets=[
            "Ed is usually negative; we often report absolute value.",
            "Linear demand is not constant-elasticity: it is elastic at high prices and inelastic at low ones.",
            "Income elasticity distinguishes normal and inferior goods.",
            "Cross-price elasticity is positive for substitutes, negative for complements.",
        ],
        examples=[
            "Insulin demand is relatively inelastic for many patients in the short run.",
            "Airline tickets on a given route can be elastic if rival carriers exist.",
        ],
        worked=[
            (
                "Revenue test",
                "Price rises from $10 to $12. Quantity falls from 100 to 80.\n"
                "1. Midpoint %ΔQ = (80−100)/90 = −22.2%. %ΔP = (12−10)/11 = 18.2%.\n"
                "2. Ed ≈ −22.2 / 18.2 ≈ −1.22 (elastic).\n"
                "3. Revenue: 10×100 = 1000; 12×80 = 960. Revenue fell, matching elastic demand.\n"
                "Rule: price up and elastic demand → revenue down.",
            ),
        ],
        pitfalls=[
            "Slope is not elasticity. Elasticity is unit-free; slope is not.",
            "A steep-looking graph can still be elastic depending on the scales.",
        ],
        review=[
            "State the midpoint formula.",
            "If demand is inelastic, what happens to revenue when price rises?",
            "Who bears a tax when demand is perfectly inelastic?",
        ],
    ),
    _topic(
        slug="gdp-accounts",
        title="GDP and National Accounts",
        overview=(
            "Gross domestic product is the market value of final goods and services produced within a "
            "country in a period. It is the headline measure of production, not a complete measure of "
            "welfare. These notes cover the three approaches, real versus nominal, and what GDP misses."
        ),
        terms=[
            ("Final good", "A good sold to its end user, not as an input to another producer."),
            ("Nominal GDP", "GDP at current prices."),
            ("Real GDP", "GDP at constant prices, used to track volume of output."),
            ("GDP deflator", "Nominal GDP / real GDP × 100, a broad price index."),
        ],
        explanations=[
            (
                "Three ways to count",
                "Expenditure: C + I + G + (X − M). Income: wages, rents, interest, profits, with adjustments. "
                "Production: value added at each stage. They match in a complete set of accounts because one "
                "person's spending is another's income. Intermediate sales are excluded to avoid double counting.",
            ),
            (
                "Real versus nominal",
                "If prices rise and quantities stay the same, nominal GDP rises but real GDP does not. "
                "Chain-weighting is the modern way to compute real GDP. Growth rates you see in the news "
                "are almost always real. Per capita real GDP is a rough living-standards proxy, still imperfect.",
            ),
            (
                "Limitations",
                "Home production, informal work, and many environmental costs are missing or poorly captured. "
                "GDP rises after a disaster if rebuilding is counted, even though people are worse off. "
                "Distribution is invisible: two countries with the same GDP per capita can have very different "
                "poverty rates.",
            ),
        ],
        bullets=[
            "Used goods are not current production; their sale is not GDP.",
            "Inventory investment counts goods produced but not yet sold.",
            "Imports are subtracted because they are in C, I, or G but were produced abroad.",
            "GNP counts nationality of owners; GDP counts location of production.",
        ],
        examples=[
            "A U.S. factory owned by a foreign firm still counts in U.S. GDP.",
            "Buying a 2010 house in 2026 is not 2026 GDP; a realtor's fee that year is.",
        ],
        worked=[
            (
                "Expenditure arithmetic",
                "C = 800, I = 200, G = 250, X = 80, M = 110.\n"
                "GDP = 800 + 200 + 250 + (80 − 110) = 1220.\n"
                "If inventories rise by 20, that 20 is already inside I.\n"
                "If you accidentally add intermediate steel sales of 50, you would double-count; leave them out.",
            ),
        ],
        pitfalls=[
            "GDP is not a happiness index.",
            "A trade deficit (X − M negative) does not by itself mean GDP is 'bad'; it is one component.",
        ],
        review=[
            "Write the expenditure identity.",
            "Why are intermediate goods excluded?",
            "Give two welfare issues GDP misses.",
        ],
    ),
    _topic(
        slug="monetary-policy",
        title="Monetary Policy and Interest Rates",
        overview=(
            "Central banks influence short-term interest rates and financial conditions to pursue inflation "
            "and employment goals. In modern practice this is mostly about setting a policy rate and guiding "
            "expectations, not about counting paper bills. These notes use a simple transmission sketch."
        ),
        terms=[
            ("Policy rate", "The short-term rate the central bank targets (for example, the federal funds rate)."),
            ("Inflation target", "A stated goal, often around 2% for many advanced-economy central banks."),
            ("Open-market operations", "Buying or selling securities to affect reserves and rates."),
            ("Liquidity trap", "Situation where extra money does not lower rates further or stimulate spending much."),
        ],
        explanations=[
            (
                "Transmission",
                "A higher policy rate tends to raise borrowing costs, cool interest-sensitive spending (housing, "
                "durables, investment), appreciate the currency, and lower demand. Lower demand reduces pressure "
                "on prices with a lag. The reverse is expansionary policy. Lags are long and variable, which is "
                "why central banks watch forecasts, not only last month's CPI.",
            ),
            (
                "Rules of thumb",
                "The Taylor-type idea: raise the real rate when inflation is above target and when output is "
                "above potential. Real rate ≈ nominal rate minus expected inflation. If inflation expectations "
                "rise one-for-one with the nominal rate, the real rate does not change and policy is not tighter.",
            ),
            (
                "Limits",
                "The effective lower bound constrains cuts. Financial crises can break transmission if banks "
                "will not lend. Supply shocks (oil, pandemics) create a nasty tradeoff: inflation up, output "
                "down. Monetary policy cannot target relative prices of one sector without side effects.",
            ),
        ],
        bullets=[
            "Independence is meant to reduce short-run political pressure to inflate.",
            "Forward guidance tries to move longer rates by shaping expected future short rates.",
            "QE buys longer-term assets when the policy rate is already near the floor.",
            "Credibility makes disinflation cheaper because expectations adjust faster.",
        ],
        examples=[
            "Volcker's early-1980s tightening is the classic costly disinflation case.",
            "Many central banks cut toward zero in 2008–09 and again in 2020.",
        ],
        worked=[
            (
                "Real versus nominal",
                "Policy rate = 5%. Expected inflation = 2%. Real policy rate ≈ 3%.\n"
                "If expected inflation jumps to 5% and the nominal rate stays 5%, the real rate ≈ 0%.\n"
                "That is an easing in disguise. To keep the real rate at 3%, the central bank would need "
                "a nominal rate near 8%. Always convert to real terms before judging stance.",
            ),
        ],
        pitfalls=[
            "Printing-money cartoons skip the interest-rate channel that actually dominates in normal times.",
            "Low rates are not always 'easy' if inflation and risk premia are lower still.",
        ],
        review=[
            "Describe one transmission channel from rates to inflation.",
            "Why do policy lags matter for rate decisions?",
            "What is the difference between nominal and real interest rates?",
        ],
    ),
    _topic(
        slug="comparative-advantage",
        title="Comparative Advantage and Gains from Trade",
        overview=(
            "Comparative advantage says a country (or person) should specialize in the good with the lower "
            "opportunity cost. Absolute advantage — being better at producing everything — does not cancel "
            "the gains from trade. This is the core micro-to-trade bridge in introductory economics."
        ),
        terms=[
            ("Absolute advantage", "Ability to produce more of a good with the same resources."),
            ("Comparative advantage", "Ability to produce a good at lower opportunity cost."),
            ("Opportunity cost", "Value of the next-best alternative given up."),
            ("Terms of trade", "The relative price at which goods exchange between partners."),
        ],
        explanations=[
            (
                "The logic",
                "Even if A is better at both cloth and wine, A should still import the good in which its "
                "edge is smaller. Specialization raises world output; trade shares the surplus. The result "
                "depends on constant-cost assumptions in the simplest Ricardian model, but the opportunity-"
                "cost idea survives in richer models.",
            ),
            (
                "Winners and losers",
                "A country can gain overall while some workers lose. Import competition hurts specific "
                "industries. That is why trade is politically hard even when aggregate GDP rises. Compensation "
                "is a policy choice, not an automatic market outcome.",
            ),
            (
                "Other reasons to trade",
                "Economies of scale, variety, and technology diffusion also drive trade. Comparative advantage "
                "is necessary vocabulary, not the whole of modern trade theory. Still, if you cannot compute "
                "opportunity costs, you are not ready for those extensions.",
            ),
        ],
        bullets=[
            "Compute opportunity cost as 'units of the other good given up'.",
            "Mutually beneficial terms of trade lie between the two opportunity costs.",
            "Autarky means no trade; consumption is limited by own production.",
            "A PPF shows production tradeoffs; trade can let consumption sit outside the PPF.",
        ],
        examples=[
            "A lawyer who types faster than her assistant should still hire the assistant if legal time is more valuable.",
            "Climate and soil create comparative advantage in certain crops.",
        ],
        worked=[
            (
                "Two-country numbers",
                "Labor hours per unit: Home — 2 for cloth, 4 for wine. Foreign — 6 for cloth, 6 for wine.\n"
                "1. Home opportunity cost of 1 cloth = 2/4 = 0.5 wine. Foreign: 6/6 = 1 wine.\n"
                "2. Home has comparative advantage in cloth (lower wine sacrificed).\n"
                "3. Foreign has comparative advantage in wine (1 cloth sacrificed versus Home's 2).\n"
                "4. Terms of trade of 1 cloth for 0.7 wine would sit between 0.5 and 1 and can benefit both.",
            ),
        ],
        pitfalls=[
            "Absolute advantage is neither necessary nor sufficient for who should export which good.",
            "Trade can raise total surplus and still reduce a particular industry's employment.",
        ],
        review=[
            "Define comparative advantage without using the word 'better'.",
            "Where must the terms of trade sit to make both sides willing?",
            "How can consumption occur outside a country's PPF?",
        ],
    ),
    _topic(
        slug="market-structures",
        title="Market Structures: Competition to Monopoly",
        overview=(
            "Market structure describes how many firms sell, whether products are identical, and how free "
            "entry is. Perfect competition, monopoly, monopolistic competition, and oligopoly are the four "
            "standard boxes. Pricing power and long-run profit depend on which box you are in."
        ),
        terms=[
            ("Price taker", "A firm that cannot influence market price and faces a horizontal demand."),
            ("Marginal revenue", "Extra revenue from selling one more unit."),
            ("Natural monopoly", "A market where one firm can serve demand at lower cost than two or more."),
            ("Nash equilibrium", "Profile of strategies where no player wants to deviate unilaterally."),
        ],
        explanations=[
            (
                "Perfect competition",
                "Many firms, identical products, free entry. P = MR = MC in the short-run optimum. Economic "
                "profit attracts entry, shifting supply until long-run profit is zero (for identical firms "
                "with U-shaped costs). The model is a benchmark for efficiency, not a photograph of every industry.",
            ),
            (
                "Monopoly",
                "One seller, barriers to entry. MR lies below demand, so the firm sets MR = MC and charges "
                "the price on the demand curve. Output is too low and price too high relative to P = MC. "
                "Deadweight loss is the efficiency critique. Patents, control of a key input, and scale can "
                "all create monopoly power.",
            ),
            (
                "Imperfect competition",
                "Monopolistic competition: many firms, differentiated products, free entry, zero long-run "
                "profit but P > MC. Oligopoly: few firms, strategic interaction. Cartels try to mimic monopoly "
                "and tend to cheat. Game theory is the toolkit: prisoners' dilemma for price wars, repeated "
                "games for tacit collusion.",
            ),
        ],
        bullets=[
            "Rule of thumb: produce where MR = MC if you can set price or quantity.",
            "Shutdown in the short run if P < AVC (competitive firm).",
            "Concentration ratios and HHI are crude industry measures.",
            "Price discrimination can raise output and also raise profits.",
        ],
        examples=[
            "A local water utility is often a regulated natural monopoly.",
            "Restaurants are a textbook monopolistic-competition story: entry, branding, thin long-run profits.",
        ],
        worked=[
            (
                "Monopoly markup",
                "Demand: P = 20 − Q. Costs: MC = AC = 4 (constant).\n"
                "1. TR = 20Q − Q², so MR = 20 − 2Q.\n"
                "2. MR = MC → 20 − 2Q = 4 → Q = 8.\n"
                "3. P = 20 − 8 = 12.\n"
                "4. Competitive benchmark would be P = MC = 4, Q = 16. Monopoly output is half in this linear example.",
            ),
        ],
        pitfalls=[
            "High accounting profit is not proof of monopoly if you have not counted opportunity cost of capital.",
            "Oligopoly is not 'a little monopoly' in a mechanical sense; strategy can go either way.",
        ],
        review=[
            "Why is MR below P for a single-price monopolist?",
            "What drives long-run profit to zero in monopolistic competition?",
            "Give one barrier to entry.",
        ],
    ),
    _topic(
        slug="externalities",
        title="Externalities and Public Goods",
        overview=(
            "Markets misfire when prices omit effects on bystanders. Negative externalities mean too much "
            "of the activity; positive externalities mean too little. Public goods add nonrivalry and "
            "nonexcludability. These notes connect diagrams to policy tools."
        ),
        terms=[
            ("Externality", "Uncompensated impact of one person's actions on a bystander."),
            ("Social cost", "Private cost plus external cost."),
            ("Public good", "Nonrival and nonexcludable good, such as basic research or a tornado siren."),
            ("Free rider", "Someone who benefits without paying."),
        ],
        explanations=[
            (
                "The efficiency gap",
                "A competitive market equates private MB and private MC. If a factory's smoke harms neighbors, "
                "social MC is higher, so the market quantity is too large. A vaccine with herd effects has "
                "social MB above private MB, so the market quantity is too small. Deadweight loss is the "
                "triangle between social and private curves from Qmarket to Qefficient.",
            ),
            (
                "Pigouvian tools and Coase",
                "A tax equal to marginal external cost, or a subsidy equal to marginal external benefit, can "
                "align incentives. Cap-and-trade sets quantity and lets a permit price emerge. Coase argued "
                "that if property rights are clear and bargaining is cheap, private negotiation can work. "
                "Bargaining is often not cheap when victims are many.",
            ),
            (
                "Public goods versus commons",
                "Public goods are underprovided because of free riding. Common resources are rival but "
                "nonexcludable (fisheries) and tend to be overused. The policy toolkit differs: government "
                "provision or contracts for public goods; quotas, property rights, or norms for commons.",
            ),
        ],
        bullets=[
            "Negative production externality: shift MC up to get social cost.",
            "Positive consumption externality: shift MB up to get social benefit.",
            "Tradable permits fix quantity; taxes fix price — uncertainty changes which is better.",
            "Not every government action is a public good; rivalry and exclusion are the tests.",
        ],
        examples=[
            "Congestion is a negative externality of driving at peak hours.",
            "Open-source software can be nonrival; funding it still faces free-rider issues.",
        ],
        worked=[
            (
                "Pigouvian tax size",
                "Private MC = 2 + Q. Demand (MB) = 12 − Q. External cost = 2 per unit (constant).\n"
                "1. Market: 12 − Q = 2 + Q → Q = 5, P = 7.\n"
                "2. Social MC = 4 + Q. Set 12 − Q = 4 + Q → Q* = 4, P* = 8.\n"
                "3. A tax of 2 per unit shifts private MC to social MC and hits Q*.\n"
                "4. Tax revenue = 2 × 4 = 8, but the efficiency gain is the avoided DWL triangle, not the revenue itself.",
            ),
        ],
        pitfalls=[
            "An externality is not just 'any side effect'; it must be unpriced.",
            "Publicly provided goods (education) can still be rival in a crowded classroom.",
        ],
        review=[
            "Draw a negative production externality and mark DWL.",
            "When might bargaining solve an externality without a tax?",
            "Contrast a public good with a common resource.",
        ],
    ),
    _topic(
        slug="fiscal-policy",
        title="Fiscal Policy and Multipliers",
        overview=(
            "Fiscal policy is the use of government spending and taxes to influence aggregate demand and, "
            "sometimes, long-run supply. In a slump with idle resources, extra spending can raise output. "
            "Crowding out, timing, and debt are the standard caveats. These notes stay in a short-run Keynesian frame, then qualify it."
        ),
        terms=[
            ("Multiplier", "Change in output per dollar of extra autonomous spending."),
            ("Automatic stabilizer", "Tax or transfer that cushions income without new legislation."),
            ("Crowding out", "Higher public borrowing raising rates and displacing private investment."),
            ("Structural deficit", "Deficit that would remain even at full employment."),
        ],
        explanations=[
            (
                "The multiplier idea",
                "If people spend a fraction c of extra income, a $1 increase in G can raise Y by 1/(1−c) in "
                "the simplest closed economy with no taxes. Taxes, imports, and higher rates shrink the "
                "multiplier. The idea is not magic: it requires spare capacity so that demand creates output "
                "rather than only prices.",
            ),
            (
                "Practical limits",
                "Legislatures are slow. By the time a stimulus bill is spent, the slump may have passed. "
                "Targeted transfers to liquidity-constrained households often have higher short-run bang. "
                "At full employment, extra G is more likely to reallocate resources than to raise real GDP.",
            ),
            (
                "Debt",
                "Deficits add to public debt. Sustainability depends on r versus g (the interest rate versus "
                "growth) and on primary balances. A crisis can justify large temporary deficits; a permanent "
                "gap between spending promises and taxes cannot be ignored. Distinguish cyclical from structural.",
            ),
        ],
        bullets=[
            "G up or T down is expansionary in the short-run demand story.",
            "Unemployment insurance is an automatic stabilizer.",
            "Ricardian equivalence is the claim that people save tax cuts if they expect later taxes — empirically incomplete.",
            "Supply-side fiscal policy (infrastructure, R&D) aims at potential output, not only current C.",
        ],
        examples=[
            "2009 stimulus packages mixed tax cuts and spending with long implementation lags for some projects.",
            "Progressive income taxes fall automatically when incomes fall, cushioning demand.",
        ],
        worked=[
            (
                "Simple multiplier",
                "MPC = 0.8, no taxes or imports. Multiplier = 1/(1−0.8) = 5.\n"
                "A $40 billion increase in G predicts ΔY = 200 billion in this toy model.\n"
                "If the marginal tax rate is 0.25, the multiplier becomes 1/(1−0.8×0.75) = 1/0.4 = 2.5.\n"
                "Always state leakages; the textbook 5 is an upper bound, not a forecast.",
            ),
        ],
        pitfalls=[
            "Do not apply a large multiplier to an economy already at capacity.",
            "The political slogan 'pay for stimulus immediately' can fight the point of countercyclical policy.",
        ],
        review=[
            "What is an automatic stabilizer? Give one example.",
            "How does crowding out work in the loanable-funds story?",
            "Why does the MPC appear in the multiplier?",
        ],
    ),
]

TOPICS: dict[str, list[Topic]] = {
    "biology": BIOLOGY,
    "history": HISTORY,
    "networking": NETWORKING,
    "economics": ECONOMICS,
}

SUPPORTED_SUBJECTS = tuple(TOPICS.keys())
