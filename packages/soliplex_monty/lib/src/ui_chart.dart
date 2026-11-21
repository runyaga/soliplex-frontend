export 'package:soliplex_catalogs/soliplex_catalogs.dart'
    show uiChartSignatures;

/// Most bars one `BarChart` draws.
const maxChartBars = 32;

/// Most points and lines one `LineChart` draws.
const maxLinePoints = 500;
const maxLineSeries = 6;

/// `(label, value)` pairs from [raw], or null unless there are 1 to
/// [maxChartBars] bars and every value is a finite number of at least zero.
List<(String, double)>? chartBars(List<Object?> raw) {
  final bars = <(String, double)>[];
  for (final bar in raw) {
    if (bar case {
      'label': final String label,
      'value': final num value,
    } when label.length <= 60 && value.isFinite && value >= 0) {
      bars.add((label, value.toDouble()));
    } else {
      return null;
    }
  }
  return bars.isEmpty || bars.length > maxChartBars ? null : bars;
}

/// One line of a `LineChart`; a null value is a gap.
typedef LineSeries = ({String label, List<double?> values});

/// The series in [raw], or null unless each has exactly [points] values
/// that are finite numbers or null, and at least one value is a number.
List<LineSeries>? lineSeries(List<Object?> raw, int points) {
  final series = <LineSeries>[];
  var any = false;
  for (final item in raw) {
    if (item case {
      'label': final String label,
      'values': final List<Object?> values,
    } when label.length <= 60 && values.length == points) {
      final parsed = <double?>[];
      for (final v in values) {
        if (v == null) {
          parsed.add(null);
        } else if (v is num && v.isFinite) {
          parsed.add(v.toDouble());
          any = true;
        } else {
          return null;
        }
      }
      series.add((label: label, values: parsed));
    } else {
      return null;
    }
  }
  if (series.isEmpty || series.length > maxLineSeries || !any) return null;
  return series;
}

/// Why the Python chart constructor's inputs are invalid, or null.
String? chartComponentError(Map<String, Object?> component) {
  switch (component['component']) {
    case 'BarChart':
      final bars = component['bars'];
      if (bars is List && bars.isEmpty) {
        return 'BarChart got no bars. Check the column names, and that '
            'rows were not all skipped.';
      }
      if (bars is! List || chartBars(bars) == null) {
        return 'BarChart bars must be 1 to $maxChartBars '
            '{"label": str, "value": number >= 0} dicts.';
      }
    case 'LineChart':
      final labels = component['labels'];
      final series = component['series'];
      if (labels is! List ||
          labels.length < 2 ||
          labels.length > maxLinePoints ||
          labels.any((label) => label is! String || label.length > 60) ||
          series is! List ||
          series.isEmpty ||
          lineSeries(series, labels.length) == null) {
        return 'LineChart takes 2 to $maxLinePoints labels and 1 to '
            '$maxLineSeries {"label": str, "values": [number or None]} '
            'dicts, each with one value per label.';
      }
  }
  return null;
}

/// Lowers the compatibility `ui` chart constructors to the graphics Chart.
/// All rendering, semantics and interaction live in soliplex_catalogs.
void lowerUiChart(Map<String, Object?> component) {
  final kind = component['component'];
  final error = chartComponentError(component);
  if (error != null) throw FormatException(error);
  final title = component['title'];
  if (title != null && (title is! String || title.length > 120)) {
    throw const FormatException(
      'Chart title must be text of at most 120 characters.',
    );
  }
  final spec = <String, Object?>{
    'kind': kind == 'BarChart' ? 'bar' : 'line',
    'title': ?title,
  };
  if (kind == 'BarChart') {
    final bars = component.remove('bars')! as List;
    spec['points'] = [
      for (var i = 0; i < bars.length; i++)
        {
          'id': 'p$i',
          ...bars[i] as Map,
          // The original ui renderer used doubles without an integer cap.
          'value': ((bars[i] as Map)['value'] as num).toDouble(),
        },
    ];
  } else {
    final labels = component.remove('labels')! as List;
    final series = component.remove('series')! as List;
    spec['series'] = [
      for (var i = 0; i < series.length; i++)
        {
          'id': 's$i',
          'label': (series[i] as Map)['label'],
          'points': [
            for (var j = 0; j < labels.length; j++)
              {
                'id': 'p$j',
                'label': labels[j],
                'value': (((series[i] as Map)['values'] as List)[j] as num?)
                    ?.toDouble(),
              },
          ],
        },
    ];
  }
  component
    ..remove('title')
    ..['component'] = 'Chart'
    ..['spec'] = spec
    ..['selection'] = <String>[]
    ..['description'] = title is String && title.isNotEmpty
        ? title
        : (kind == 'BarChart' ? 'Bars' : 'Lines');
}
