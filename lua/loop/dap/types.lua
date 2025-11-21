---@meta
---@diagnostic disable: missing-fields

--====================================================================--
-- Core DAP Protocol Types (strictly valid EmmyLua)
--====================================================================--
---@class loop.dap.proto.ProtocolMessage
---@field seq integer
---@field type "request" | "response" | "event"

---@class loop.dap.proto.Request : loop.dap.proto.ProtocolMessage
---@field command string
---@field arguments table|nil

---@class loop.dap.proto.Response : loop.dap.proto.ProtocolMessage
---@field request_seq integer
---@field success boolean
---@field command string
---@field message string|nil
---@field body table|nil

---@class loop.dap.proto.Event : loop.dap.proto.ProtocolMessage
---@field event string
---@field body table|nil

--====================================================================--
-- Common Types
--====================================================================--
---@class loop.dap.proto.Source
---@field name string|nil
---@field path string|nil
---@field sourceReference integer|nil
---@field presentationHint "normal"|"emphasize"|"deemphasize"|nil
---@field origin string|nil
---@field sources loop.dap.proto.Source[]|nil
---@field adapterData any
---@field checksums table[]|nil

---@class loop.dap.proto.SourceBreakpoint
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil

---@class loop.dap.proto.StackFrame
---@field id integer
---@field name string
---@field source loop.dap.proto.Source|nil
---@field line integer
---@field column integer
---@field endLine integer|nil
---@field endColumn integer|nil
---@field presentationHint "normal"|"label"|"subtle"|nil

---@class loop.dap.proto.Thread
---@field id integer
---@field name string

---@class loop.dap.proto.Scope
---@field name string
---@field variablesReference integer
---@field expensive boolean
---@field source loop.dap.proto.Source|nil
---@field line integer|nil
---@field column integer|nil

---@class loop.dap.proto.VariablePresentationHint
---@field kind "property"|"method"|"class"|"data"|"event"|"baseClass"|"innerClass"|"interface"|"mostDerivedClass"|"virtual"|nil
---@field visibility "public"|"private"|"protected"|"internal"|"final"|nil
---@field lazy boolean|nil

---@class loop.dap.proto.Variable
---@field name string
---@field value string
---@field type string|nil
---@field presentationHint loop.dap.proto.VariablePresentationHint|nil
---@field evaluateName string|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

--====================================================================--
-- Specific Request/Response Bodies
--====================================================================--
---@class loop.dap.proto.InitializeRequestArguments
---@field clientID string|nil
---@field clientName string|nil
---@field adapterID string
---@field locale string|nil
---@field linesStartAt1 boolean
---@field columnsStartAt1 boolean
---@field pathFormat "path"|"uri"
---@field supportsVariableType boolean|nil
---@field supportsRunInTerminalRequest boolean|nil

---@class loop.dap.proto.Capabilities
---@field supportsConfigurationDoneRequest boolean|nil
---@field supportsFunctionBreakpoints boolean|nil
---@field supportsConditionalBreakpoints boolean|nil
---@field supportsHitConditionalBreakpoints boolean|nil
---@field supportsEvaluateForHovers boolean|nil
---@field supportsStepBack boolean|nil
---@field supportsSetVariable boolean|nil
---@field supportsExceptionInfoRequest boolean|nil
---@field supportsDataBreakpoints boolean|nil

---@class loop.dap.proto.SetBreakpointsArguments
---@field source loop.dap.proto.Source
---@field breakpoints loop.dap.proto.SourceBreakpoint[]|nil
---@field lines integer[]|nil
---@field sourceModified boolean|nil

---@class loop.dap.proto.Breakpoint
---@field verified boolean
---@field id integer|nil
---@field line integer|nil
---@field message string|nil
---@field source loop.dap.proto.Source|nil

---@class loop.dap.proto.SetBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.ThreadsResponse
---@field threads loop.dap.proto.Thread[]

---@class loop.dap.proto.StackTraceArguments
---@field threadId integer
---@field startFrame integer|nil
---@field levels integer|nil

---@class loop.dap.proto.StackTraceResponse
---@field stackFrames loop.dap.proto.StackFrame[]
---@field totalFrames integer|nil

---@class loop.dap.proto.ScopesArguments
---@field frameId integer

---@class loop.dap.proto.ScopesResponse
---@field scopes loop.dap.proto.Scope[]

---@class loop.dap.proto.VariablesArguments
---@field variablesReference integer
---@field filter "indexed"|"named"|nil
---@field start integer|nil
---@field count integer|nil

---@class loop.dap.proto.VariablesResponse
---@field variables loop.dap.proto.Variable[]

---@class loop.dap.proto.ContinueArguments
---@field threadId integer

---@class loop.dap.proto.ContinueResponse
---@field allThreadsContinued boolean|nil

---@class loop.dap.proto.EvaluateArguments
---@field expression string
---@field frameId integer|nil
---@field context "watch"|"repl"|"hover"|"clipboard"|nil

---@class loop.dap.proto.EvaluateResponse
---@field result string
---@field type string|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

--====================================================================--
-- Additional Request Argument Types (all official DAP spec)
--====================================================================--
---@class loop.dap.proto.SetFunctionBreakpointsArguments
---@field breakpoints table[]

---@class loop.dap.proto.SetExceptionBreakpointsArguments
---@field filters string[]
---@field filterOptions table[]|nil
---@field exceptionOptions table[]|nil

---@class loop.dap.proto.PauseArguments
---@field threadId integer

---@class loop.dap.proto.NextArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.StepInArguments
---@field threadId integer
---@field targetId integer|nil
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.StepOutArguments
---@field threadId integer

---@class loop.dap.proto.StepBackArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.ReverseContinueArguments
---@field threadId integer

---@class loop.dap.proto.GotoArguments
---@field threadId integer
---@field targetId integer

---@class loop.dap.proto.RestartFrameArguments
---@field frameId integer

---@class loop.dap.proto.SetExpressionArguments
---@field expression string
---@field frameId integer|nil
---@field value string

---@class loop.dap.proto.SetVariableArguments
---@field variablesReference integer
---@field name string
---@field value string

---@class loop.dap.proto.SourceArguments
---@field source loop.dap.proto.Source
---@field sourceReference integer

---@class loop.dap.proto.ExceptionInfoArguments
---@field threadId integer

---@class loop.dap.proto.BreakpointLocationsArguments
---@field source loop.dap.proto.Source
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil

--====================================================================--
-- Events
--====================================================================--
---@class loop.dap.proto.StoppedEvent
---@field reason "step"|"breakpoint"|"exception"|"pause"|"entry"|"goto"
---@field threadId integer|nil
---@field allThreadsStopped boolean|nil

---@class loop.dap.proto.OutputEvent
---@field category "console"|"important"|"stdout"|"stderr"|nil
---@field output string
---@field source loop.dap.proto.Source|nil
---@field line integer|nil