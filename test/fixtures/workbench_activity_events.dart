// Actual ToolReturn.metadata events; freshness checked by backend tests.
const publishedEventsJson = '''[
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
              "title": "Intake",
              "question": "",
              "districts": [],
              "acknowledged": false
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
                  "question",
                  "districts",
                  "acknowledged",
                  "submit"
                ]
              },
              {
                "id": "provenance",
                "component": "Text",
                "text": "Form created by the assistant"
              },
              {
                "id": "question",
                "component": "TextField",
                "label": "Question * (max 240 characters)",
                "value": {
                  "@path": "/question"
                }
              },
              {
                "id": "districts",
                "component": "ChoicePicker",
                "label": "Districts * (choose 1\u20132)",
                "variant": "multipleSelection",
                "options": [
                  {
                    "value": "north",
                    "label": "North"
                  },
                  {
                    "value": "south",
                    "label": "South"
                  }
                ],
                "value": {
                  "@path": "/districts"
                },
                "displayStyle": "chips"
              },
              {
                "id": "acknowledged",
                "component": "CheckBox",
                "label": "Acknowledged *",
                "value": {
                  "@path": "/acknowledged"
                }
              },
              {
                "id": "submit",
                "component": "Button",
                "child": "submit_label",
                "action": {
                  "event": {
                    "name": "submit_intake",
                    "context": {
                      "question": {
                        "@path": "/question"
                      },
                      "districts": {
                        "@path": "/districts"
                      },
                      "acknowledged": {
                        "@path": "/acknowledged"
                      }
                    }
                  }
                }
              },
              {
                "id": "submit_label",
                "component": "Text",
                "text": "Submit"
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
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_4",
                    "parentId": "node_3",
                    "children": [],
                    "kind": "surface",
                    "title": "Intake",
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
  },
  {
    "type": "ACTIVITY_SNAPSHOT",
    "messageId": "activity_5",
    "activityType": "a2ui-surface",
    "content": {
      "a2ui_operations": [
        {
          "version": "1.0",
          "createSurface": {
            "surfaceId": "surface_6",
            "catalogId": "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
          }
        },
        {
          "version": "1.0",
          "updateDataModel": {
            "surfaceId": "surface_6",
            "path": "/",
            "value": {
              "spec": {
                "kind": "bar",
                "title": "Counts",
                "points": [
                  {
                    "id": "north",
                    "label": "North",
                    "value": 80.0
                  }
                ]
              }
            }
          }
        },
        {
          "version": "1.0",
          "updateComponents": {
            "surfaceId": "surface_6",
            "components": [
              {
                "id": "root",
                "component": "Chart",
                "@catalogId": "urn:soliplex:catalog:graphics:2",
                "spec": {
                  "kind": "bar",
                  "title": "Counts",
                  "points": [
                    {
                      "id": "north",
                      "label": "North",
                      "value": 80.0
                    }
                  ]
                },
                "selection": [],
                "description": "Counts"
              }
            ]
          }
        }
      ],
      "workbenchPublication": {
        "role": "content",
        "activityMessageId": "activity_5",
        "surfaceId": "surface_6"
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
                "layoutRevision": 2,
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
                    "children": [
                      "node_7"
                    ],
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
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_4",
                    "parentId": "node_3",
                    "children": [],
                    "kind": "surface",
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_1",
                      "surfaceId": "surface_2"
                    }
                  },
                  {
                    "id": "node_7",
                    "parentId": "r_canvas",
                    "children": [
                      "node_8"
                    ],
                    "kind": "panel",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_8",
                    "parentId": "node_7",
                    "children": [],
                    "kind": "surface",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_5",
                      "surfaceId": "surface_6"
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
const publishedProgramEventsJson = '''[
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
                "layoutRevision": 3,
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
                    "children": [
                      "node_7",
                      "node_9"
                    ],
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
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_4",
                    "parentId": "node_3",
                    "children": [],
                    "kind": "surface",
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_1",
                      "surfaceId": "surface_2"
                    }
                  },
                  {
                    "id": "node_7",
                    "parentId": "r_canvas",
                    "children": [
                      "node_8"
                    ],
                    "kind": "panel",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_8",
                    "parentId": "node_7",
                    "children": [],
                    "kind": "surface",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_5",
                      "surfaceId": "surface_6"
                    }
                  },
                  {
                    "id": "node_9",
                    "parentId": "r_canvas",
                    "children": [],
                    "kind": "window",
                    "title": "Python",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
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
  },
  {
    "type": "ACTIVITY_SNAPSHOT",
    "messageId": "activity_10",
    "activityType": "a2ui-surface",
    "content": {
      "a2ui_operations": [
        {
          "version": "1.0",
          "createSurface": {
            "surfaceId": "surface_11",
            "catalogId": "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
          }
        },
        {
          "version": "1.0",
          "updateDataModel": {
            "surfaceId": "surface_11",
            "path": "/",
            "value": {
              "source": "print(1)",
              "title": "Demo",
              "output": ""
            }
          }
        },
        {
          "version": "1.0",
          "updateComponents": {
            "surfaceId": "surface_11",
            "components": [
              {
                "id": "root",
                "component": "PythonRepl",
                "@catalogId": "urn:soliplex:catalog:lab:1",
                "source": {
                  "@path": "/source"
                },
                "outputPath": "/output",
                "onFailure": {
                  "event": {
                    "name": "workbench.program.repair",
                    "context": {
                      "result": {
                        "@path": "/output"
                      }
                    }
                  }
                },
                "onWorkbench": {
                  "event": {
                    "name": "workbench.program.layout",
                    "context": {
                      "invocationId": {
                        "@path": "/output/invocationId"
                      },
                      "actions": {
                        "@path": "/output/actions"
                      }
                    }
                  }
                },
                "onRun": {
                  "event": {
                    "name": "workbench.program.run_result",
                    "context": {
                      "side": "client",
                      "engine": "monty-1.3.0",
                      "invocationId": {
                        "@path": "/output/invocationId"
                      },
                      "chainId": {
                        "@path": "/output/chainId"
                      },
                      "outcome": {
                        "@path": "/output/outcome"
                      },
                      "output": {
                        "@path": "/output/output"
                      }
                    }
                  }
                }
              }
            ]
          }
        }
      ],
      "workbenchPublication": {
        "role": "program",
        "activityMessageId": "activity_10",
        "surfaceId": "surface_11"
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
                "layoutRevision": 4,
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
                    "children": [
                      "node_7",
                      "node_9"
                    ],
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
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_4",
                    "parentId": "node_3",
                    "children": [],
                    "kind": "surface",
                    "title": "Intake",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_1",
                      "surfaceId": "surface_2"
                    }
                  },
                  {
                    "id": "node_7",
                    "parentId": "r_canvas",
                    "children": [
                      "node_8"
                    ],
                    "kind": "panel",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_8",
                    "parentId": "node_7",
                    "children": [],
                    "kind": "surface",
                    "title": "Counts",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_5",
                      "surfaceId": "surface_6"
                    }
                  },
                  {
                    "id": "node_9",
                    "parentId": "r_canvas",
                    "children": [
                      "node_12"
                    ],
                    "kind": "window",
                    "title": "Python",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {}
                  },
                  {
                    "id": "node_12",
                    "parentId": "node_9",
                    "children": [],
                    "kind": "surface",
                    "title": "Demo",
                    "size": "medium",
                    "visibility": "open",
                    "payload": {
                      "activityMessageId": "activity_10",
                      "surfaceId": "surface_11"
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
