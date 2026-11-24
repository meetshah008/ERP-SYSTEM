/// Common display-name cleanup for values coming from DB/session.
///
/// Old sessions or badly entered setup data can leave numeric placeholders
/// such as `123456` where a company name should be. Real names are untouched.
const String fallbackCompanyName = 'Manufacturing Co';

String cleanCompanyName(dynamic value, [String fallback = fallbackCompanyName]) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty || raw.toLowerCase() == 'null') return fallback;
  if (num.tryParse(raw) != null) return fallback;
  return raw;
}
