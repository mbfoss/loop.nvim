return [[
{
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "object",
    "title": "Task Configuration",
    "description": "Supported variables:\n- ${HOME}: User home directory\n- ${FILE}: Full path to current file\n- ${FILENAME}: File name with extension (e.g., main.cpp)\n- ${FILEEXT}: File extension (e.g., cpp)\n- ${FILEROOT}: File name without extension (e.g., main)\n- ${FILEDIR}: Directory containing the file\n- ${PROJDIR}: Project root directory\n- ${CWD}: Current working directory\n- ${FILETYPE}: Language/file type (e.g., cpp, py)\n- ${TMPDIR}: System temporary directory\n- ${DATE}: Current date (YYYY-MM-DD)\n- ${TIME}: Current time (HH:MM:SS)\n- ${TIMESTAMP}: Unix timestamp",
    "properties": {
        "$schema": {
            "type": "string"
        },
        "tasks": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "pattern": "^.+$",
                        "description": "Unique task name"
                    },
                    "type": {
                        "type": "string",
                        "enum": [
                            "vimcmd",
                            "tool",
                            "app",
                            "debug"
                        ],
                        "description": "Task type. Use colon for subtypes (e.g., debug:launch)."
                    },
                    "command": {
                        "oneOf": [
                            {
                                "type": "string",
                                "pattern": "^.+$",
                                "description": "Executable command as a string"
                            },
                            {
                                "type": "array",
                                "items": {
                                    "type": "string",
                                    "pattern": "^.+$"
                                },
                                "minItems": 1,
                                "description": "Executable command as an array of strings"
                            }
                        ]
                    },
                    "cwd": {
                        "type": "string",
                        "description": "Working directory for the task"
                    },
                    "env": {
                        "type": "object",
                        "additionalProperties": {
                            "type": "string"
                        },
                        "description": "Environment variables to set"
                    },
                    "quickfix_matcher": {
                        "type": "string",
                        "description": "Matcher used to fill the quickfix list"
                    },
                    "debug": {
                        "type": "object",
                        "description": "Debugger configuration for 'debug' tasks",
                        "properties": {
                            "type": {
                                "type": "string",
                                "enum": [
                                    "local",
                                    "remote"
                                ],
                                "description": "debug type: local (default), remote"
                            },
                            "host": {
                                "type": "string",
                                "description": "for remote mode"
                            },
                            "port": {
                                "type": "number",
                                "description": "for remote mode"
                            },
                            "adapter": {
                                "type": "string",
                                "description": "The debug adapter to use"
                            },
                            "run_in_terminal": {
                                "type": "boolean",
                                "description": "Whether to start the debugger in a terminal"
                            },
                            "stop_on_entry": {
                                "type": "boolean",
                                "description": "Whether to stop immediately on entry"
                            }
                        },
                        "required": ["type"],
                        "additionalProperties": false
                    },
                    "depends_on": {
                        "type": "array",
                        "items": {
                            "type": "string",
                            "pattern": "^.+$"
                        },
                        "description": "List of task names this task depends on"
                    }
                },
                "required": [
                    "name",
                    "type",
                    "command"
                ],
                "additionalProperties": false
            }
        }
    },
    "required": [
        "$schema",
        "tasks"
    ],
    "additionalProperties": false
}
]]
