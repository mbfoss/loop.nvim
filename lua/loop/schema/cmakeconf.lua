return [[
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "properties": {
    "$schema": {
      "type": "string"
    },
    "config": {
      "type": "object",
      "properties": {
        "cmake_path": {
          "type": "string",
          "pattern": "^.+$"
        },
        "profiles": {
          "type": "array",
          "items": {
            "type": "object",
            "properties": {
              "name": {
                "type": "string",
                "pattern": "^.+$"
              },
              "build_type": {
                "type": "string",
                "enum": ["Debug", "Release", "RelWithDebInfo", "MinSizeRel"]
              },
              "source_dir": {
                "type": "string",
                "pattern": "^.+$"
              },
              "build_dir": {
                "type": "string",
                "pattern": "^.+$"
              },
              "configure_args": {
                "type": "array",
                "items": {
                    "type": "string"
                }
              },
              "build_tool_args": {
               "type": "array",
                "items": {
                    "type": "string"
                }
              },
              "prob_matcher": {
                "oneOf": [
                  {
                    "type": "string",
                    "enum": [
                      "$gcc",
                      "$tsc-watch",
                      "$eslint-stylish",
                      "$msCompile",
                      "$lessCompile"
                    ]
                  },
                  {
                    "type": "object",
                    "properties": {
                      "regexp": { "type": "string", "pattern": "^.+$" },
                      "file": { "type": "number" },
                      "line": { "type": "number" },
                      "column": { "type": "number" },
                      "severity": { "type": "number" },
                      "message": { "type": "number" }
                    },
                    "required": ["regexp"],
                    "additionalProperties": false
                  }
                ]
              },
              "run": {
                "type": "object",
                "patternProperties": {
                  "^.+$": {
                    "type": "object",
                    "properties": {
                      "cwd": { "type": "string" },
                      "args": {
                        "type": "array",
                        "items": {"type": "string" }
                      },
                      "env": {
                        "type": "array",
                        "items": { "type": "string" }
                      }
                    },
                    "additionalProperties": false
                  }
                },
                "additionalProperties": false
              }
            },
            "required": [
              "name",
              "build_type",
              "source_dir",
              "build_dir",
              "prob_matcher"
            ],
            "additionalProperties": false
          }
        }
      },
      "required": ["cmake_path", "profiles"],
      "additionalProperties": false
    }
  }
}

]]
