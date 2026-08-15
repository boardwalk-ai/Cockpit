# Sample Materials Generator

CLI that writes realistic `.txt` and `.md` study notes for **upload and end-to-end testing**. It does not call the documents API and does not change production backend behavior.

## Where it lives

`Backend/scripts/generate_sample_materials.py`

Topic banks: `Backend/scripts/sample_materials_catalog.py`

Run it from the `Backend/` directory so the `scripts` package imports cleanly.

## Usage

```bash
cd Backend
python -m scripts.generate_sample_materials \
  --count <N> \
  --subject <subject> \
  --size <short|medium|long> \
  --out <output-folder>
```

All four flags are required.

| Flag | Meaning |
| ---- | ------- |
| `--count` | Exact number of files to write (positive integer) |
| `--subject` | Subject bank to draw from |
| `--size` | Approximate document length |
| `--out` | Output folder (created if missing) |

Invalid subjects, sizes, or a non-positive `--count` fail with a short error.

## Supported subjects

- `biology`
- `history`
- `networking`
- `economics`

## Supported sizes

- `short` — one topic, fewer sections
- `medium` — one full topic with examples, pitfalls, and review
- `long` — several related topics, worked examples, and a longer recap

Generated files mix `.md` and `.txt`, use readable unique names, and vary titles, headings, examples, and structure so they are not identical boilerplate.

## Example commands

```bash
cd Backend

python -m scripts.generate_sample_materials \
  --count 4 --subject biology --size short --out ./sample_materials/biology-short

python -m scripts.generate_sample_materials \
  --count 3 --subject networking --size medium --out ./sample_materials/networking-medium

python -m scripts.generate_sample_materials \
  --count 2 --subject economics --size long --out ./sample_materials/economics-long
```

## Example output folder

`--out ./sample_materials/biology-short` creates that folder under `Backend/` and writes files such as:

```
Backend/sample_materials/biology-short/
  biology-photosynthesis-short-01.md
  biology-membrane-transport-short-02.txt
  biology-dna-replication-short-03.md
  biology-mendelian-genetics-short-04.txt
```

Use those files as upload fixtures. Do not commit generated notes unless you mean to.
