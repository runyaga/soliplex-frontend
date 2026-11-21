/// The chart kind, title, author description and data points for screen readers.
String chartSemanticsLabel(Map<Object?, Object?> spec, String description) {
  final entries = <String>[];
  void points(Object? data) {
    if (data is List) {
      for (final item in data.take(32).whereType<Map>()) {
        entries.add(
          '${item['label'] ?? item['id']}: ${_value(item.containsKey('value') ? item['value'] : item['y'] ?? item['close'])}',
        );
      }
    }
  }

  points(spec['points'] ?? spec['slices'] ?? spec['candles']);
  if (spec['series'] case final List series) {
    for (final item in series.whereType<Map>()) {
      entries.add('${item['label'] ?? item['id']}');
      points(item['points']);
      if (item['values'] case final List values) {
        entries.add(values.map(_value).join(', '));
      }
    }
  }
  if (spec['kind'] == 'gauge') {
    entries.add(
      '${_value(spec['value'])}${spec['unit'] ?? ''}, scale ${_value(spec['min_value'])} to ${_value(spec['max_value'])}',
    );
  }
  final title = spec['title'];
  final note = description.trim().replaceFirst(RegExp(r'\.$'), '');
  final heading = title == null || note.isEmpty || note == title
      ? '${title ?? note}'
      : '$title. $note';
  return '${spec['kind']} chart: $heading; ${entries.join(', ')}';
}

String _value(Object? value) =>
    value is num && value == value.truncateToDouble()
    ? value.toStringAsFixed(0)
    : value == null
    ? 'gap'
    : '$value';

/// Formats a chart value without `.0`, or with two decimals for bar labels.
String chartNumber(num value) => value == value.truncateToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2);
