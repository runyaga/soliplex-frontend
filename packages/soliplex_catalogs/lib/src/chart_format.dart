/// Text for a chart value: whole numbers as integers, others to two decimals.
///
/// A nonzero value that rounds to zero keeps two decimals and its sign, so a
/// value just below zero still reads as below zero.
String chartNumberText(num value) {
  if (value == value.truncateToDouble()) return value.toInt().toString();
  final fixed = value.toStringAsFixed(2);
  final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  return trimmed == '0' || trimmed == '-0' ? fixed : trimmed;
}
