// Generated from the adjacent catalog JSON fixtures.
const a2uiCatalogDocuments = <String, String>{
  'chart': '''
{
  "catalogId": "urn:soliplex:catalog:graphics:2",
  "protocolVersion": "1.0",
  "components": {
    "Chart": {
      "type": "object",
      "properties": {
        "component": {"const": "Chart"},
        "spec": {
          "type": "object",
          "properties": {
            "kind": {"enum": ["bar", "line"]},
            "series": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "id": {"type": "string"},
                  "label": {"type": "string"},
                  "points": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "id": {"type": "string"},
                        "label": {"type": "string"},
                        "value": {"type": "number"}
                      },
                      "required": ["id", "label", "value"]
                    }
                  }
                },
                "required": ["id", "label", "points"]
              }
            }
          },
          "required": ["kind", "series"]
        }
      },
      "required": ["component", "spec"]
    }
  }
}
''',
  'data': '''
{
  "catalogId": "urn:soliplex:catalog:data:1",
  "protocolVersion": "1.0",
  "components": {
    "DataTable": {
      "type": "object",
      "properties": {
        "component": {"const": "DataTable"},
        "columns": {"type": "array", "items": {"type": "string"}},
        "rows": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "id": {"type": "string"},
              "label": {"type": "string"},
              "value": {"type": "number"}
            },
            "required": ["id", "label", "value"]
          }
        }
      },
      "required": ["component", "columns", "rows"]
    }
  }
}
''',
  'intake': '''
{
  "catalogId": "urn:soliplex:catalog:intake:1",
  "protocolVersion": "1.0",
  "components": {
    "IntakeForm": {
      "type": "object",
      "properties": {
        "component": {"const": "IntakeForm"},
        "title": {"type": "string"},
        "question": {"type": "string"},
        "districts": {"type": "array", "items": {"enum": ["north", "south"]}},
        "acknowledged": {"const": true}
      },
      "required": ["component", "title", "question", "districts", "acknowledged"]
    }
  }
}
''',
};
