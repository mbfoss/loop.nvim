return [[


{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Loop Task Configuration",
  "description": "Configuration file for loop.nvim tasks.\n\nSupported template variables:\n- ${HOME}, ${FILE}, ${FILENAME}, ${FILEEXT}, ${FILEROOT}\n- ${FILEDIR}, ${PROJDIR}, ${CWD}, ${FILETYPE}\n- ${TMPDIR}, ${DATE}, ${TIME}, ${TIMESTAMP}",
  "type": "object",
  "properties": {
    "$schema": { "type": "string" },
    "tasks": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "name": {
            "type": "string",
            "minLength": 1,
            "description": "Non-empty unique task name (supports ${VAR} templates)"
          },
          "type": {
            "type": "string",
            "enum": [ "vimcmd", "tool", "app", "debug" ],
            "description": "Task category"
          },
          "command": {
            "oneOf": [
              { "type": "string", "minLength": 1 },
              {
                "type": "array",
                "minItems": 1,
                "items": { "type": "string", "minLength": 1 }
              },
              { "type": "null" }
            ],
            "description": "Command to run (string or array). Required for vimcmd/tool/app, optional for debug."
          },
          "cwd": {
            "type": [ "string", "null" ],
            "description": "Optional working directory (supports ${VAR} templates)"
          },
          "env": {
            "type": [ "object", "null" ],
            "additionalProperties": { "type": "string" },
            "description": "Optional environment variables"
          },
          "quickfix_matcher": {
            "type": [ "string", "null" ],
            "description": "Optional quickfix matcher name"
          },
          "depends_on": {
            "type": [ "array", "null" ],
            "items": { "type": "string", "minLength": 1 },
            "description": "Optional list of dependent task names"
          },
          "debugger": {
            "type": [ "string", "null" ],
            "description": "Required for type = 'debug'. Name of the debug adapter."
          },
          "debug": {
            "type": "object",
            "additionalProperties": true
          }
        },
        "required": [ "name", "type" ],
        "additionalProperties": false
      }
    }
  },
  "required": [ "tasks" ],
  "additionalProperties": false
}

]]
