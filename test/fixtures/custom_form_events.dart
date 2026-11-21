// Generated from the real place_form wrapper; checked by Python.
const customFormEventsJson = r'''[
  {
    "type": "ACTIVITY_SNAPSHOT",
    "messageId": "activity_1",
    "activityType": "a2ui-surface",
    "content": {
      "a2ui_operations": [
        {
          "version": "1.0",
          "createSurface": {
            "surfaceId": "surface_2",
            "catalogId": "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
          }
        },
        {
          "version": "1.0",
          "updateDataModel": {
            "surfaceId": "surface_2",
            "path": "/",
            "value": {
              "title": "Scenario survey",
              "fields": [
                {
                  "name": "name",
                  "label": "Name",
                  "kind": "text",
                  "required": true,
                  "options": null,
                  "multiple": false,
                  "min": null,
                  "max": null,
                  "max_length": 30
                },
                {
                  "name": "notes",
                  "label": "Notes",
                  "kind": "textarea",
                  "required": false,
                  "options": null,
                  "multiple": false,
                  "min": null,
                  "max": null,
                  "max_length": 100
                },
                {
                  "name": "age",
                  "label": "Age",
                  "kind": "number",
                  "required": false,
                  "options": null,
                  "multiple": false,
                  "min": 1.0,
                  "max": 120.0,
                  "max_length": null
                },
                {
                  "name": "color",
                  "label": "Color",
                  "kind": "choice",
                  "required": false,
                  "options": [
                    {
                      "value": "Red",
                      "label": "Red"
                    },
                    {
                      "value": "Blue",
                      "label": "Blue"
                    }
                  ],
                  "multiple": false,
                  "min": null,
                  "max": null,
                  "max_length": null
                },
                {
                  "name": "districts",
                  "label": "Districts",
                  "kind": "choice",
                  "required": false,
                  "options": [
                    {
                      "value": "North",
                      "label": "North"
                    },
                    {
                      "value": "South",
                      "label": "South"
                    }
                  ],
                  "multiple": true,
                  "min": null,
                  "max": null,
                  "max_length": null
                },
                {
                  "name": "subscribe",
                  "label": "Subscribe",
                  "kind": "checkbox",
                  "required": false,
                  "options": null,
                  "multiple": false,
                  "min": null,
                  "max": null,
                  "max_length": null
                },
                {
                  "name": "day",
                  "label": "Day",
                  "kind": "date",
                  "required": false,
                  "options": null,
                  "multiple": false,
                  "min": null,
                  "max": null,
                  "max_length": null
                }
              ],
              "values": {
                "name": "",
                "notes": "",
                "age": "",
                "color": [],
                "districts": [],
                "subscribe": false,
                "day": ""
              }
            }
          }
        },
        {
          "version": "1.0",
          "updateComponents": {
            "surfaceId": "surface_2",
            "components": [
              {
                "id": "root",
                "component": "Column",
                "children": [
                  "provenance",
                  "field_0",
                  "field_1",
                  "field_2",
                  "field_3",
                  "field_4",
                  "field_5",
                  "field_6",
                  "submit",
                  "receipt"
                ]
              },
              {
                "id": "provenance",
                "component": "Text",
                "text": "Form created by the assistant"
              },
              {
                "id": "field_0",
                "label": "Name * (max 30 characters)",
                "value": {
                  "@path": "/values/name"
                },
                "component": "TextField",
                "variant": "shortText"
              },
              {
                "id": "field_1",
                "label": "Notes (max 100 characters)",
                "value": {
                  "@path": "/values/notes"
                },
                "component": "TextField",
                "variant": "longText"
              },
              {
                "id": "field_2",
                "label": "Age (1–120)",
                "value": {
                  "@path": "/values/age"
                },
                "component": "TextField",
                "variant": "number"
              },
              {
                "id": "field_3",
                "label": "Color",
                "value": {
                  "@path": "/values/color"
                },
                "component": "ChoicePicker",
                "variant": "mutuallyExclusive",
                "options": [
                  {
                    "value": "Red",
                    "label": "Red"
                  },
                  {
                    "value": "Blue",
                    "label": "Blue"
                  }
                ],
                "displayStyle": "checkbox"
              },
              {
                "id": "field_4",
                "label": "Districts",
                "value": {
                  "@path": "/values/districts"
                },
                "component": "ChoicePicker",
                "variant": "multipleSelection",
                "options": [
                  {
                    "value": "North",
                    "label": "North"
                  },
                  {
                    "value": "South",
                    "label": "South"
                  }
                ],
                "displayStyle": "checkbox"
              },
              {
                "id": "field_5",
                "label": "Subscribe",
                "value": {
                  "@path": "/values/subscribe"
                },
                "component": "CheckBox"
              },
              {
                "id": "field_6",
                "label": "Day",
                "value": {
                  "@path": "/values/day"
                },
                "component": "DateTimeInput",
                "enableDate": true,
                "enableTime": false
              },
              {
                "id": "submit",
                "component": "Button",
                "child": "submit_label",
                "action": {
                  "event": {
                    "name": "submit_form",
                    "context": {
                      "values": {
                        "@path": "/values"
                      }
                    }
                  }
                }
              },
              {
                "id": "submit_label",
                "component": "Text",
                "text": "Submit"
              },
              {
                "id": "receipt",
                "component": "Text",
                "text": ""
              }
            ]
          }
        }
      ],
      "workbenchPublication": {
        "role": "content",
        "activityMessageId": "activity_1",
        "surfaceId": "surface_2"
      }
    },
    "replace": true
  },
  {
    "type": "ACTIVITY_SNAPSHOT",
    "messageId": "wb-layout-b5aa70e53b389d160f6b20d4",
    "activityType": "a2ui-surface",
    "content": {
      "a2ui_operations": [
        {
          "version": "1.0",
          "createSurface": {
            "surfaceId": "wb-control-b5aa70e53b389d160f6b20d4",
            "catalogId": "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
          }
        },
        {
          "version": "1.0",
          "updateDataModel": {
            "surfaceId": "wb-control-b5aa70e53b389d160f6b20d4",
            "path": "/",
            "value": {
              "summary": "Workbench",
              "workbench": {
                "schemaVersion": 1,
                "layoutRevision": 1,
                "rootId": "wb_root",
                "nodes": [
                  {
                    "id": "wb_root",
                    "parentId": null,
                    "children": [
                      "r_chat",
                      "r_left",
                      "r_right",
                      "r_canvas",
                      "r_tray"
                    ],
                    "kind": "workspace",
                    "title": "Workspace",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "r_chat",
                    "parentId": "wb_root",
                    "children": [],
                    "kind": "region",
                    "title": "Chat",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "role": "chat"
                    }
                  },
                  {
                    "id": "r_left",
                    "parentId": "wb_root",
                    "children": [
                      "node_3"
                    ],
                    "kind": "region",
                    "title": "Left",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "role": "left"
                    }
                  },
                  {
                    "id": "r_right",
                    "parentId": "wb_root",
                    "children": [],
                    "kind": "region",
                    "title": "Right",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "role": "right"
                    }
                  },
                  {
                    "id": "r_canvas",
                    "parentId": "wb_root",
                    "children": [],
                    "kind": "region",
                    "title": "Canvas",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "role": "canvas"
                    }
                  },
                  {
                    "id": "r_tray",
                    "parentId": "wb_root",
                    "children": [],
                    "kind": "region",
                    "title": "Tray",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "role": "tray"
                    }
                  },
                  {
                    "id": "node_3",
                    "parentId": "r_left",
                    "children": [
                      "node_4"
                    ],
                    "kind": "panel",
                    "title": "Scenario survey",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_4",
                    "parentId": "node_3",
                    "children": [],
                    "kind": "surface",
                    "title": "Scenario survey",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_1",
                      "surfaceId": "surface_2"
                    }
                  }
                ],
                "shared": {}
              }
            }
          }
        },
        {
          "version": "1.0",
          "updateComponents": {
            "surfaceId": "wb-control-b5aa70e53b389d160f6b20d4",
            "components": [
              {
                "id": "root",
                "component": "Text",
                "text": {
                  "@path": "/summary"
                }
              }
            ]
          }
        }
      ],
      "workbenchPublication": {
        "role": "layout",
        "activityMessageId": "wb-layout-b5aa70e53b389d160f6b20d4",
        "surfaceId": "wb-control-b5aa70e53b389d160f6b20d4"
      }
    },
    "replace": true
  }
]''';
