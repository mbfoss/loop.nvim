---@meta
---@diagnostic disable: missing-fields

--====================================================================--
-- Core DAP Protocol Types (strictly valid EmmyLua)
--====================================================================--

---@class DAP.ProtocolMessage
---@field seq integer
---@field type "request" | "response" | "event"

---@class DAP.Request : DAP.ProtocolMessage
---@field command string
---@field arguments table|nil

---@class DAP.Response : DAP.ProtocolMessage
---@field request_seq integer
---@field success boolean
---@field command string
---@field message string|nil
---@field body table|nil

---@class DAP.Event : DAP.ProtocolMessage
---@field event string
---@field body table|nil

--====================================================================--
-- Common Types (all named classes — no inline tables)
--====================================================================--

---@class DAP.Source
---@field name string|nil
---@field path string|nil
---@field sourceReference integer|nil
---@field presentationHint "normal"|"emphasize"|"deemphasize"|nil
---@field origin string|nil
---@field sources DAP.Source[]|nil
---@field adapterData any
---@field checksums table[]|nil

---@class DAP.SourceBreakpoint
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil

---@class DAP.StackFrame
---@field id integer
---@field name string
---@field source DAP.Source|nil
---@field line integer
---@field column integer
---@field endLine integer|nil
---@field endColumn integer|nil
---@field presentationHint "normal"|"label"|"subtle"|nil

---@class DAP.Thread
---@field id integer
---@field name string

---@class DAP.Scope
---@field name string
---@field variablesReference integer
---@field expensive boolean
---@field source DAP.Source|nil
---@field line integer|nil
---@field column integer|nil

---@class DAP.VariablePresentationHint
---@field kind "property"|"method"|"class"|"data"|"event"|"baseClass"|"innerClass"|"interface"|"mostDerivedClass"|"virtual"|nil
---@field visibility "public"|"private"|"protected"|"internal"|"final"|nil
---@field lazy boolean|nil

---@class DAP.Variable
---@field name string
---@field value string
---@field type string|nil
---@field presentationHint DAP.VariablePresentationHint|nil
---@field evaluateName string|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

--====================================================================--
-- Specific Request/Response Bodies (each as a separate class)
--====================================================================--

---@class DAP.InitializeRequestArguments
---@field clientID string|nil
---@field clientName string|nil
---@field adapterID string
---@field locale string|nil
---@field linesStartAt1 boolean
---@field columnsStartAt1 boolean
---@field pathFormat "path"|"uri"
---@field supportsVariableType boolean|nil
---@field supportsRunInTerminalRequest boolean|nil

---@class DAP.Capabilities
---@field supportsConfigurationDoneRequest boolean|nil
---@field supportsFunctionBreakpoints boolean|nil
---@field supportsConditionalBreakpoints boolean|nil
---@field supportsHitConditionalBreakpoints boolean|nil
---@field supportsEvaluateForHovers boolean|nil
---@field supportsStepBack boolean|nil
---@field supportsSetVariable boolean|nil
---@field supportsExceptionInfoRequest boolean|nil
---@field supportsDataBreakpoints boolean|nil

---@class DAP.SetBreakpointsArguments
---@field source DAP.Source
---@field breakpoints DAP.SourceBreakpoint[]|nil
---@field lines integer[]|nil
---@field sourceModified boolean|nil

---@class DAP.Breakpoint
---@field verified boolean
---@field id integer|nil
---@field line integer|nil
---@field message string|nil
---@field source DAP.Source|nil

---@class DAP.SetBreakpointsResponse
---@field breakpoints DAP.Breakpoint[]

---@class DAP.ThreadsResponse
---@field threads DAP.Thread[]

---@class DAP.StackTraceArguments
---@field threadId integer
---@field startFrame integer|nil
---@field levels integer|nil

---@class DAP.StackTraceResponse
---@field stackFrames DAP.StackFrame[]
---@field totalFrames integer|nil

---@class DAP.ScopesArguments
---@field frameId integer

---@class DAP.ScopesResponse
---@field scopes DAP.Scope[]

---@class DAP.VariablesArguments
---@field variablesReference integer
---@field filter "indexed"|"named"|nil
---@field start integer|nil
---@field count integer|nil

---@class DAP.VariablesResponse
---@field variables DAP.Variable[]

---@class DAP.ContinueArguments
---@field threadId integer

---@class DAP.ContinueResponse
---@field allThreadsContinued boolean|nil

---@class DAP.EvaluateArguments
---@field expression string
---@field frameId integer|nil
---@field context "watch"|"repl"|"hover"|"clipboard"|nil

---@class DAP.EvaluateResponse
---@field result string
---@field type string|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

--====================================================================--
-- Events
--====================================================================--

---@class DAP.StoppedEvent
---@field reason "step"|"breakpoint"|"exception"|"pause"|"entry"|"goto"
---@field threadId integer|nil
---@field allThreadsStopped boolean|nil

---@class DAP.OutputEvent
---@field category "console"|"important"|"stdout"|"stderr"|nil
---@field output string
---@field source DAP.Source|nil
---@field line integer|nil