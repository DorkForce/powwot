/// Subject classification for MySpool alert emails.
library;

const String powerOffSubject = 'MySpool POWER OFF Alert';
const String powerOnSubject = 'MySpool POWER ON Alert';

enum AlertKind { powerOff, powerOn, other }

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// Classifies an email subject. Matching is "contains", case-insensitive and
/// whitespace-tolerant, so prefixes like "Fwd:" or "[MySpool]" still match.
AlertKind classifySubject(String? subject) {
  if (subject == null) return AlertKind.other;
  final s = _norm(subject);
  if (s.contains(_norm(powerOffSubject))) return AlertKind.powerOff;
  if (s.contains(_norm(powerOnSubject))) return AlertKind.powerOn;
  return AlertKind.other;
}
