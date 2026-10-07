//! Splitting pages into passages for retrieval: whole paragraphs where they
//! fit (~1,600 characters, ~400 tokens), a short overlap carried into the
//! next passage, never across a page, each passage remembering its page and
//! the heading it sits under. Replaces "every 512 words".

use crate::extract::Page;

#[derive(Debug, Clone, PartialEq)]
pub struct Chunk {
    pub text: String,
    pub page: Option<i32>,
    pub heading: Option<String>,
}

pub const TARGET: usize = 1600;
pub const OVERLAP: usize = 200;

fn chars(s: &str) -> usize {
    s.chars().count()
}

/// A heading: a markdown `#` line, or one short line with no closing
/// punctuation (a title, not a sentence).
pub fn heading_of(block: &str) -> Option<String> {
    let line = block.trim();
    if line.contains('\n') {
        return None;
    }
    if let Some(h) = line.strip_prefix('#') {
        let h = h.trim_start_matches('#').trim();
        return (!h.is_empty()).then(|| h.to_string());
    }
    let words = line.split_whitespace().count();
    let ends = line.ends_with(['.', ',', ';', ':', '?', '!', '"', '”', ')']);
    (chars(line) <= 80 && (1..=12).contains(&words) && !ends && line.chars().next().is_some_and(char::is_alphanumeric))
        .then(|| line.to_string())
}

/// The last ~`n` characters of `s`, starting at a word.
fn tail(s: &str, n: usize) -> &str {
    let total = chars(s);
    if total <= n {
        return s;
    }
    let start = s.char_indices().nth(total - n).map(|(i, _)| i).unwrap_or(0);
    let rest = &s[start..];
    match rest.find(char::is_whitespace) {
        Some(i) => rest[i..].trim_start(),
        None => rest,
    }
}

/// A block longer than the target, cut at sentence ends, else at words.
fn split_long(block: &str, target: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur = String::new();
    // Sentences: keep the punctuation; Burmese ends sentences with "။".
    let mut pieces: Vec<String> = Vec::new();
    let mut s = String::new();
    for ch in block.chars() {
        s.push(ch);
        if matches!(ch, '.' | '?' | '!' | '။') {
            pieces.push(std::mem::take(&mut s));
        }
    }
    if !s.trim().is_empty() {
        pieces.push(s);
    }
    for p in pieces {
        let p = p.trim();
        if chars(p) > target {
            // A "sentence" with no stops: by words.
            for w in p.split_whitespace() {
                if chars(&cur) + chars(w) + 1 > target && !cur.is_empty() {
                    out.push(std::mem::take(&mut cur));
                }
                if !cur.is_empty() {
                    cur.push(' ');
                }
                cur.push_str(w);
            }
            continue;
        }
        if chars(&cur) + chars(p) + 1 > target && !cur.is_empty() {
            out.push(std::mem::take(&mut cur));
        }
        if !cur.is_empty() {
            cur.push(' ');
        }
        cur.push_str(p);
    }
    if !cur.trim().is_empty() {
        out.push(cur);
    }
    out
}

pub fn chunk_pages(pages: &[Page], target: usize, overlap: usize) -> Vec<Chunk> {
    let mut out: Vec<Chunk> = Vec::new();
    let mut heading: Option<String> = None;
    for page in pages {
        let mut buf = String::new();
        let mut buf_heading = heading.clone();
        let flush = |buf: &mut String, h: &Option<String>, out: &mut Vec<Chunk>| {
            let text = buf.trim();
            if !text.is_empty() {
                out.push(Chunk { text: text.to_string(), page: page.number, heading: h.clone() });
            }
            buf.clear();
        };
        let text = page.text.replace("\r\n", "\n");
        let blocks: Vec<&str> = text
            .split("\n\n")
            .flat_map(|b| {
                // Lines that are headings on their own break a block too.
                let mut parts = Vec::new();
                let mut start = 0;
                for (i, line) in b.split_inclusive('\n').scan(0, |pos, l| {
                    let at = *pos;
                    *pos += l.len();
                    Some((at, l))
                }) {
                    if line.trim_start().starts_with('#') && i > start {
                        parts.push(&b[start..i]);
                        start = i;
                    }
                }
                parts.push(&b[start..]);
                parts
            })
            .map(str::trim)
            .filter(|b| !b.is_empty())
            .collect();
        for block in blocks {
            if let Some(h) = heading_of(block) {
                // A new section starts a new passage — unless the one open
                // is still tiny; then it keeps its first heading.
                if chars(&buf) > overlap {
                    flush(&mut buf, &buf_heading, &mut out);
                }
                if buf.trim().is_empty() {
                    buf_heading = Some(h.clone());
                }
                heading = Some(h);
                continue;
            }
            let block = block.split_whitespace().collect::<Vec<_>>().join(" ");
            let parts = if chars(&block) > target { split_long(&block, target) } else { vec![block] };
            for part in parts {
                if !buf.is_empty() && chars(&buf) + chars(&part) + 2 > target {
                    let carry = tail(&buf, overlap).to_string();
                    flush(&mut buf, &buf_heading, &mut out);
                    buf_heading = heading.clone();
                    buf.push_str(&carry);
                }
                if !buf.is_empty() {
                    buf.push_str("\n\n");
                }
                buf.push_str(&part);
            }
        }
        flush(&mut buf, &buf_heading, &mut out);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn page(n: i32, text: &str) -> Page {
        Page { number: Some(n), text: text.to_string() }
    }

    #[test]
    fn headings() {
        assert_eq!(heading_of("# Congestion control").as_deref(), Some("Congestion control"));
        assert_eq!(heading_of("2.3 Slow start").as_deref(), Some("2.3 Slow start"));
        assert_eq!(heading_of("TCP halves the window on loss."), None);
        assert_eq!(heading_of("line one\nline two"), None);
    }

    #[test]
    fn pages_headings_and_overlap() {
        let para = "TCP sends data in segments and waits for acknowledgements. ".repeat(12);
        let pages = vec![
            page(1, &format!("# Transport\n\n{para}\n\n{para}\n\n{para}")),
            page(2, &format!("Congestion window\n\n{para}")),
        ];
        let chunks = chunk_pages(&pages, TARGET, OVERLAP);
        assert!(chunks.len() >= 3);
        assert!(chunks.iter().all(|c| chars(&c.text) <= TARGET + OVERLAP + 4));
        assert_eq!(chunks[0].page, Some(1));
        assert_eq!(chunks[0].heading.as_deref(), Some("Transport"));
        let last = chunks.last().unwrap();
        assert_eq!(last.page, Some(2));
        assert_eq!(last.heading.as_deref(), Some("Congestion window"));
        // The second passage on page 1 starts with the end of the first.
        let tail_words: Vec<_> = chunks[0].text.split_whitespace().rev().take(3).collect();
        assert!(tail_words.iter().all(|w| chunks[1].text.contains(w)));
    }

    #[test]
    fn long_burmese_paragraph_is_cut_at_sentence_ends() {
        let sentence = "ကွန်ရက်ပေါ်တွင် ဒေတာများကို အပိုင်းလိုက် ပို့သည်။ ";
        let pages = vec![Page { number: None, text: sentence.repeat(80) }];
        let chunks = chunk_pages(&pages, TARGET, OVERLAP);
        assert!(chunks.len() >= 2);
        assert!(chunks.iter().all(|c| chars(&c.text) <= TARGET + OVERLAP + 4));
        assert!(chunks[0].text.trim_end().ends_with('။'));
    }

    #[test]
    fn small_sections_keep_their_first_heading() {
        let md = "# Week 3 notes

TCP halves its window on loss.

## Slow start

The window doubles each round trip.";
        let c = chunk_pages(&[Page { number: None, text: md.into() }], TARGET, OVERLAP);
        assert_eq!(c.len(), 1);
        assert_eq!(c[0].heading.as_deref(), Some("Week 3 notes"));
    }

    #[test]
    fn empty_pages_make_nothing() {
        assert!(chunk_pages(&[page(1, "  \n\n ")], TARGET, OVERLAP).is_empty());
    }
}
