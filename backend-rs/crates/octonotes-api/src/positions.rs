//! Fractional indexing over base-62 digits: a key strictly between any two keys,
//! so inserting or moving a block never renumbers the others. Keys compare
//! byte-wise (`COLLATE "C"`), and the Flutter client uses the same alphabet.

const DIGITS: &[u8] = b"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

fn digit(c: u8) -> Option<usize> {
    DIGITS.iter().position(|d| *d == c)
}

/// A key is non-empty, base-62 only, and does not end in '0' (so a key
/// between two others always exists).
pub fn is_valid(key: &str) -> bool {
    !key.is_empty() && key.len() <= 256 && key.bytes().all(|b| digit(b).is_some()) && !key.ends_with('0')
}

/// A key strictly between `a` and `b` (`None` = open end). Port of the
/// midpoint step of David Greenspan's `fractional-indexing`. Requires `a < b`
/// and valid keys (no trailing '0').
pub fn between(a: Option<&str>, b: Option<&str>) -> String {
    midpoint(a.unwrap_or("").as_bytes(), b.map(str::as_bytes))
}

fn midpoint(a: &[u8], b: Option<&[u8]>) -> String {
    if let Some(b) = b {
        // Shared prefix (a padded with '0'): keep it and recurse on the rest.
        let mut n = 0;
        while n < b.len() && a.get(n).copied().unwrap_or(b'0') == b[n] {
            n += 1;
        }
        if n > 0 {
            let head = String::from_utf8(b[..n].to_vec()).expect("ascii");
            let tail_a = if n < a.len() { &a[n..] } else { &[][..] };
            return head + &midpoint(tail_a, Some(&b[n..]));
        }
    }
    let da = a.first().and_then(|c| digit(*c)).unwrap_or(0);
    let db = match b {
        Some(b) => b.first().and_then(|c| digit(*c)).unwrap_or(DIGITS.len()),
        None => DIGITS.len(),
    };
    if db - da > 1 {
        (DIGITS[(da + db).div_ceil(2)] as char).to_string()
    } else if let Some(b) = b.filter(|b| b.len() > 1) {
        (b[0] as char).to_string()
    } else {
        let rest = if a.len() > 1 { &a[1..] } else { &[][..] };
        (DIGITS[da] as char).to_string() + &midpoint(rest, None)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn check(a: Option<&str>, b: Option<&str>) -> String {
        let k = between(a, b);
        assert!(is_valid(&k), "invalid key {k}");
        if let Some(a) = a {
            assert!(a < k.as_str(), "{a} < {k}");
        }
        if let Some(b) = b {
            assert!(k.as_str() < b, "{k} < {b}");
        }
        k
    }

    #[test]
    fn open_ends() {
        check(None, None);
        check(Some("V"), None);
        check(None, Some("V"));
        check(Some("zzz"), None);
        check(None, Some("01"));
    }

    #[test]
    fn adjacent_and_nested() {
        check(Some("a"), Some("b"));
        check(Some("a"), Some("a1"));
        check(Some("az"), Some("b"));
        check(Some("1"), Some("2"));
        check(Some("Vz"), Some("W"));
    }

    #[test]
    fn many_inserts_stay_ordered() {
        // Append 200 times, then insert 200 times at the front, then between.
        let mut keys = vec![check(None, None)];
        for _ in 0..200 {
            let last = keys.last().cloned();
            keys.push(check(last.as_deref(), None));
        }
        for _ in 0..200 {
            let first = keys.first().cloned();
            keys.insert(0, check(None, first.as_deref()));
        }
        for _ in 0..200 {
            let (a, b) = (keys[10].clone(), keys[11].clone());
            keys.insert(11, check(Some(&a), Some(&b)));
        }
        let mut sorted = keys.clone();
        sorted.sort();
        assert_eq!(keys, sorted);
    }
}
