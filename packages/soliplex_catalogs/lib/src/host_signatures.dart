/// Positional order of every v1.0 basic-catalog constructor, from the Track B
/// binding contract. Each name is also accepted as a keyword.
const basicSignatures = <String, List<String>>{
  'Text': ['text', 'variant', 'weight'],
  'Image': ['url', 'description', 'fit', 'variant', 'weight'],
  'Icon': ['name', 'weight'],
  'Video': ['url', 'posterUrl', 'weight'],
  'AudioPlayer': ['url', 'description', 'weight'],
  'Row': ['children', 'justify', 'align', 'weight'],
  'Column': ['children', 'justify', 'align', 'weight'],
  'List': ['children', 'direction', 'align', 'weight'],
  'Card': ['child', 'weight'],
  'Tabs': ['tabs', 'weight'],
  'Modal': ['trigger', 'content', 'weight'],
  'Divider': ['axis', 'weight'],
  'Button': ['child', 'variant', 'action', 'weight'],
  'TextField': ['label', 'value', 'placeholder', 'variant', 'weight'],
  'CheckBox': ['label', 'value', 'weight'],
  'ChoicePicker': [
    'label',
    'variant',
    'options',
    'value',
    'displayStyle',
    'filterable',
    'weight',
  ],
  'Slider': ['label', 'min', 'max', 'value', 'steps', 'weight'],
  'DateTimeInput': [
    'value',
    'enableDate',
    'enableTime',
    'min',
    'max',
    'label',
    'weight',
  ],
};

const graphicsSignature = [
  'spec',
  'selection',
  'description',
  'height',
  'selected',
  'action',
  'weight',
];

/// Positional order of the chart constructors in the Python `ui` module.
const uiChartSignatures = <String, List<String>>{
  'BarChart': ['bars', 'title', 'action', 'weight'],
  'LineChart': ['labels', 'series', 'title', 'weight'],
};
