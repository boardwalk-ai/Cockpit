/// Fractional block positions, the server's base-62 keys
/// (`octonotes-api/src/positions.rs`): a key strictly between [a] and [b]
/// (null = open end). Requires `a < b` and valid keys (no trailing '0').
String positionBetween(String? a, String? b) => _mid(a ?? '', b);

/// A key after [last] (or the first key).
String positionAfter(String? last) => positionBetween(last, null);

const _digits = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

String _mid(String a, String? b) {
  if (b != null) {
    // Shared prefix (a padded with '0'): keep it and recurse on the rest.
    var n = 0;
    while (n < b.length && (n < a.length ? a[n] : '0') == b[n]) {
      n++;
    }
    if (n > 0) return b.substring(0, n) + _mid(n < a.length ? a.substring(n) : '', b.substring(n));
  }
  final da = a.isEmpty ? 0 : _digits.indexOf(a[0]);
  final db = b == null || b.isEmpty ? _digits.length : _digits.indexOf(b[0]);
  if (db - da > 1) return _digits[(da + db + 1) ~/ 2];
  if (b != null && b.length > 1) return b[0];
  return _digits[da] + _mid(a.length > 1 ? a.substring(1) : '', null);
}
