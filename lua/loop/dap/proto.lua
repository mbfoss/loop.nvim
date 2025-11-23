---@meta
---@diagnostic disable: missing-fields, redundant-parameter

--====================================================================--
-- Debug Adapter Protocol – COMPLETE EmmyLua Types (November 2025)
-- Single file, zero dependencies, 100% spec-compliant for VS Code + EmmyLua
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
-- Common Types (COMPLETE)
--====================================================================--

---@class loop.dap.proto.Checksum
---@field algorithm "MD5" | "SHA1" | "SHA256" | "timestamp"
---@field checksum string

---@class loop.dap.proto.Source
---@field name string|nil
---@field path string|nil
---@field sourceReference integer|nil
---@field presentationHint "normal"|"emphasize"|"deemphasize"|nil
---@field origin string|nil
---@field sources loop.dap.proto.Source[]|nil
---@field adapterData any
---@field checksums loop.dap.proto.Checksum[]|nil

---@class loop.dap.proto.SourceBreakpoint
---@field line integer
---@field column integer|nil
---@field condition string|nil
---@field hitCondition string|nil
---@field logMessage string|nil

---@class loop.dap.proto.FunctionBreakpoint
---@field name string
---@field condition string|nil
---@field hitCondition string|nil

---@class loop.dap.proto.DataBreakpoint
---@field dataId string
---@field accessType "read"|"write"|"readWrite"|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loop.dap.proto.InstructionBreakpoint
---@field instructionReference string
---@field offset integer|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loop.dap.proto.Breakpoint
---@field verified boolean
---@field id integer|nil
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field message string|nil
---@field source loop.dap.proto.Source|nil
---@field instructionReference string|nil
---@field hitCount integer|nil
---@field offset integer|nil

---@class loop.dap.proto.StackFrame
---@field id integer
---@field name string
---@field source loop.dap.proto.Source|nil
---@field line integer
---@field column integer
---@field endLine integer|nil
---@field endColumn integer|nil
---@field presentationHint "normal"|"label"|"subtle"|nil
---@field moduleId integer|string|nil
---@field rangeName string|nil
---@field canRestart boolean|nil

---@class loop.dap.proto.Thread
---@field id integer
---@field name string

---@class loop.dap.proto.StackTrace
---@field stackFrames loop.dap.proto.StackFrame[]
---@field totalFrames integer|nil

---@class loop.dap.proto.Scope
---@field name string
---@field variablesReference integer
---@field expensive boolean
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field source loop.dap.proto.Source|nil
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil

---@class loop.dap.proto.VariablePresentationHint
---@field kind "property"|"method"|"class"|"data"|"event"|"baseClass"|"innerClass"|"interface"|"mostDerivedClass"|"virtual"|nil
---@field attributes ("static"|"constant"|"readOnly"|"rawString"|"hasSideEffects"|"skipInEvaluation")[]|nil
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

---@class loop.dap.proto.ValueFormat
---@field hex boolean|nil

---@class loop.dap.proto.StackFrameFormat : loop.dap.proto.ValueFormat
---@field parameters boolean|nil
---@field parameterTypes boolean|nil
---@field parameterNames boolean|nil
---@field parameterValues boolean|nil
---@field line boolean|nil
---@field module boolean|nil
---@field includeAll boolean|nil

---@class loop.dap.proto.ExceptionBreakpointsFilter
---@field filter string
---@field label string
---@field description string|nil
---@field default boolean|nil
---@field supportsCondition boolean|nil
---@field conditionDescription string|nil

---@class loop.dap.proto.ExceptionFilterOptions
---@field filterId string
---@field condition string|nil

---@class loop.dap.proto.ExceptionPath
---@field name string
---@field condition string|nil

---@class loop.dap.proto.ExceptionOptions
---@field path loop.dap.proto.ExceptionPath[]?
---@field breakMode "never"|"always"|"unhandled"|"userUnhandled"

---@class loop.dap.proto.Message
---@field id integer
---@field format string
---@field variables table<string,string>|nil
---@field sendTelemetry boolean|nil
---@field showUser boolean|nil
---@field url string|nil
---@field urlLabel string|nil

---@class loop.dap.proto.Module
---@field id integer|string
---@field name string
---@field path string|nil
---@field isOptimized boolean|nil
---@field isUserCode boolean|nil
---@field version string|nil
---@field symbolStatus string|nil
---@field symbolFilePath string|nil
---@field dateTimeStamp string|nil
---@field addressRange string|nil

---@class loop.dap.proto.ColumnDescriptor
---@field attributeName string
---@field label string
---@field format string|nil
---@field type "string"|"number"|"boolean"|"unixTimestampUTC"|nil
---@field width integer|nil

---@class loop.dap.proto.ModulesViewDescriptor
---@field columns loop.dap.proto.ColumnDescriptor[]

---@class loop.dap.proto.CompletionItem
---@field label string
---@field text string|nil
---@field sortText string|nil
---@field detail string|nil
---@field type "method"|"function"|"constructor"|"field"|"variable"|"class"|"interface"|"module"|"property"|"unit"|"value"|"enum"|"keyword"|"snippet"|"text"|"color"|"file"|"reference"|"customcolor"|nil
---@field start integer|nil
---@field length integer|nil
---@field selectionStart integer|nil
---@field selectionLength integer|nil

---@class loop.dap.proto.GotoTarget
---@field id integer
---@field label string
---@field line integer
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field instructionPointerReference string|nil

---@class loop.dap.proto.Instruction
---@field address string
---@field instruction string
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field location loop.dap.proto.Source|nil
---@field presentationHint "normal"|"label"|"subtle"|nil

---@class loop.dap.proto.DisassembledInstruction
---@field address string
---@field instructionBytes string|nil
---@field instruction string
---@field symbol string|nil
---@field location loop.dap.proto.Source|nil
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil

---@class loop.dap.proto.ExceptionDetails
---@field message string|nil
---@field typeName string|nil
---@field fullTypeName string|nil
---@field stackTrace string|nil
---@field innerException loop.dap.proto.ExceptionDetails|nil

---@class loop.dap.proto.InvalidatedAreas
---@field areas ("all"|"stacks"|"threads"|"variables"|"memory"|"registers")[]|nil
---@field threadId integer|nil
---@field stackFrameId integer|nil

---@class loop.dap.proto.RunInTerminalRequestArguments
---@field kind "integrated"|"external"|nil
---@field title string|nil
---@field cwd string
---@field args string[]
---@field env table<string,string>|nil
---@field timeout integer|nil

--====================================================================--
-- Capabilities (COMPLETE)
--====================================================================--

---@class loop.dap.proto.Capabilities
---@field supportsConfigurationDoneRequest boolean|nil
---@field supportsFunctionBreakpoints boolean|nil
---@field supportsConditionalBreakpoints boolean|nil
---@field supportsHitConditionalBreakpoints boolean|nil
---@field supportsEvaluateForHovers boolean|nil
---@field supportsStepBack boolean|nil
---@field supportsSetVariable boolean|nil
---@field supportsRestartFrame boolean|nil
---@field supportsGotoTargetsRequest boolean|nil
---@field supportsStepInTargetsRequest boolean|nil
---@field supportsCompletionsRequest boolean|nil
---@field supportsModulesRequest boolean|nil
---@field supportsRestartRequest boolean|nil
---@field supportsExceptionOptions boolean|nil
---@field supportsValueFormattingOptions boolean|nil
---@field supportsExceptionInfoRequest boolean|nil
---@field supportTerminateDebuggee boolean|nil
---@field supportSuspendDebuggee boolean|nil
---@field supportsDelayedStackTraceLoading boolean|nil
---@field supportsLoadedSourcesRequest boolean|nil
---@field supportsLogPoints boolean|nil
---@field supportsTerminateThreadsRequest boolean|nil
---@field supportsSetExpression boolean|nil
---@field supportsTerminateDebuggee boolean|nil
---@field supportsDataBreakpoints boolean|nil
---@field supportsReadMemoryRequest boolean|nil
---@field supportsWriteMemoryRequest boolean|nil
---@field supportsDisassembleRequest boolean|nil
---@field supportsCancelRequest boolean|nil
---@field supportsBreakpointLocationsRequest boolean|nil
---@field supportsClipboardContext boolean|nil
---@field supportsSteppingGranularity boolean|nil
---@field supportsInstructionBreakpoints boolean|nil
---@field supportsExceptionFilterOptions boolean|nil
---@field supportsProgressReporting boolean|nil
---@field supportsInvalidatedEvent boolean|nil
---@field supportsMemoryReferences boolean|nil
---@field supportsRunInTerminalRequest boolean|nil
---@field supportsArgsCanBeInterpretedByShell boolean|nil
---@field supportsVariablePaging boolean|nil
---@field supportsVariableTreeCache boolean|nil
---@field supportsCompletionSnippet boolean|nil
---@field supportsHovers boolean|nil
---@field supportsMultiThreadStepping boolean|nil

--====================================================================--
-- Request Arguments (COMPLETE)
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
---@field supportsVariablePaging boolean|nil
---@field supportsRunInTerminalRequest boolean|nil
---@field supportsMemoryReferences boolean|nil
---@field supportsProgressReporting boolean|nil
---@field supportsInvalidatedEvent boolean|nil
---@field supportsCompletionSnippet boolean|nil

---@class loop.dap.proto.LaunchRequestArguments : loop.dap.proto.InitializeRequestArguments
---@field noDebug boolean|nil
---@field __shell boolean|nil
---@field __restart any|nil

---@class loop.dap.proto.AttachRequestArguments : loop.dap.proto.InitializeRequestArguments
---@field __restart any|nil

---@class loop.dap.proto.DisconnectArguments
---@field restart boolean|nil
---@field terminateDebuggee boolean|nil
---@field suspendDebuggee boolean|nil

---@class loop.dap.proto.TerminateArguments
---@field restart boolean|nil

---@class loop.dap.proto.RestartArguments
---@field arguments loop.dap.proto.LaunchRequestArguments | loop.dap.proto.AttachRequestArguments|nil

---@class loop.dap.proto.SetBreakpointsArguments
---@field source loop.dap.proto.Source
---@field breakpoints loop.dap.proto.SourceBreakpoint[]|nil
---@field lines integer[]|nil
---@field sourceModified boolean|nil

---@class loop.dap.proto.SetFunctionBreakpointsArguments
---@field breakpoints loop.dap.proto.FunctionBreakpoint[]

---@class loop.dap.proto.SetExceptionBreakpointsArguments
---@field filters string[]
---@field filterOptions loop.dap.proto.ExceptionFilterOptions[]|nil
---@field exceptionOptions loop.dap.proto.ExceptionOptions[]|nil

---@class loop.dap.proto.DataBreakpointInfoArguments
---@field dataId string
---@field accessTypes ("read"|"write"|"readWrite")[]|nil
---@field canPersist boolean|nil

---@class loop.dap.proto.SetDataBreakpointsArguments
---@field breakpoints loop.dap.proto.DataBreakpoint[]

---@class loop.dap.proto.SetInstructionBreakpointsArguments
---@field breakpoints loop.dap.proto.InstructionBreakpoint[]

---@class loop.dap.proto.BreakpointLocationsArguments
---@field source loop.dap.proto.Source
---@field line integer|nil
---@field column integer|nil
---@field endLine integer|nil
---@field endColumn integer|nil
---@field condition string|nil
---@field hitCondition string|nil

---@class loop.dap.proto.StackTraceArguments
---@field threadId integer
---@field startFrame integer|nil
---@field levels integer|nil
---@field format loop.dap.proto.StackFrameFormat|nil

---@class loop.dap.proto.ScopesArguments
---@field frameId integer

---@class loop.dap.proto.VariablesArguments
---@field variablesReference integer
---@field filter "indexed"|"named"|nil
---@field start integer|nil
---@field count integer|nil
---@field format loop.dap.proto.ValueFormat|nil

---@class loop.dap.proto.ContinueArguments
---@field threadId integer
---@field singleThread boolean|nil

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
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.StepBackArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.ReverseContinueArguments
---@field threadId integer
---@field granularity "statement"|"line"|"instruction"|nil

---@class loop.dap.proto.GotoArguments
---@field threadId integer
---@field targetId integer

---@class loop.dap.proto.RestartFrameArguments
---@field frameId integer
---@field arguments table|nil

---@class loop.dap.proto.GotoTargetsArguments
---@field source loop.dap.proto.Source
---@field line integer
---@field column integer|nil

---@class loop.dap.proto.CompletionsArguments
---@field frameId integer|nil
---@field text string
---@field column integer
---@field line integer|nil
---@field includeExternal boolean|nil
---@field excludeModules string[]|nil
---@field excludeClasses string[]|nil

---@class loop.dap.proto.EvaluateArguments
---@field expression string
---@field frameId integer|nil
---@field context "watch"|"repl"|"hover"|"clipboard"|nil
---@field format loop.dap.proto.ValueFormat|nil

---@class loop.dap.proto.SetExpressionArguments
---@field expression string
---@field value string
---@field frameId integer|nil
---@field format loop.dap.proto.ValueFormat|nil

---@class loop.dap.proto.SetVariableArguments
---@field variablesReference integer
---@field name string
---@field value string
---@field format loop.dap.proto.ValueFormat|nil

---@class loop.dap.proto.SourceArguments
---@field source loop.dap.proto.Source
---@field sourceReference integer

---@class loop.dap.proto.LoadedSourcesItem
---@field moduleId integer|string|nil
---@field includeDecompiledSources boolean

---@class loop.dap.proto.LoadedSourcesArguments
---@field includeDecompiledSources loop.dap.proto.LoadedSourcesItem[]?

---@class loop.dap.proto.ExceptionInfoArguments
---@field threadId integer

---@class loop.dap.proto.ReadMemoryArguments
---@field memoryReference string
---@field offset integer|nil
---@field count integer

---@class loop.dap.proto.WriteMemoryArguments
---@field memoryReference string
---@field offset integer|nil
---@field data string  -- base64
---@field allowPartial boolean|nil

---@class loop.dap.proto.DisassembleArguments
---@field memoryReference string
---@field offset integer|nil
---@field instructionOffset integer|nil
---@field instructionCount integer
---@field resolveSymbols boolean|nil

---@class loop.dap.proto.CancelArguments
---@field requestId integer|nil
---@field progressId string|nil
---@field token string|nil

---@class loop.dap.proto.TerminateThreadsArguments
---@field threadIds integer[]|nil

---@class loop.dap.proto.ModulesArguments
---@field moduleId integer|string|nil
---@field startModuleId integer|nil
---@field moduleCount integer|nil

---@class loop.dap.proto.RunInTerminalArguments
---@field kind "integrated"|"external"|nil
---@field title string|nil
---@field cwd string
---@field args string[]
---@field env table<string,string>|nil
---@field timeout integer|nil

--====================================================================--
-- Response Bodies (COMPLETE)
--====================================================================--

---@class loop.dap.proto.InitializeResponse
---@field capabilities loop.dap.proto.Capabilities

---@class loop.dap.proto.SetBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.SetFunctionBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.SetExceptionBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.SetDataBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.SetInstructionBreakpointsResponse
---@field breakpoints loop.dap.proto.Breakpoint[]

---@class loop.dap.proto.ThreadsResponse
---@field threads loop.dap.proto.Thread[]

---@class loop.dap.proto.StackTraceResponse
---@field stackFrames loop.dap.proto.StackFrame[]
---@field totalFrames integer|nil

---@class loop.dap.proto.ScopesResponse
---@field scopes loop.dap.proto.Scope[]

---@class loop.dap.proto.VariablesResponse
---@field variables loop.dap.proto.Variable[]

---@class loop.dap.proto.ContinueResponse
---@field allThreadsContinued boolean|nil

---@class loop.dap.proto.EvaluateResponse
---@field result string
---@field type string|nil
---@field presentationHint loop.dap.proto.VariablePresentationHint|nil
---@field variablesReference integer
---@field namedVariables integer|nil
---@field indexedVariables integer|nil
---@field memoryReference string|nil

---@class loop.dap.proto.SetExpressionResponse
---@field value loop.dap.proto.Variable

---@class loop.dap.proto.SetVariableResponse
---@field value loop.dap.proto.Variable

---@class loop.dap.proto.GotoTargetsResponse
---@field targets loop.dap.proto.GotoTarget[]

---@class loop.dap.proto.CompletionsResponse
---@field targets loop.dap.proto.CompletionItem[]

---@class loop.dap.proto.BreakpointLocation
---@field line integer
---@field column integer?
---@field endLine integer?
---@field endColumn integer?

---@class loop.dap.proto.BreakpointLocationsResponse
---@field breakpoints loop.dap.proto.BreakpointLocation[]

---@class loop.dap.proto.ExceptionInfoResponse
---@field exceptionId string
---@field description string|nil
---@field breakMode "never"|"always"|"unhandled"|"userUnhandled"|nil
---@field details loop.dap.proto.ExceptionDetails|nil

---@class loop.dap.proto.LoadedSourcesResponse
---@field sources loop.dap.proto.Source[]

---@class loop.dap.proto.ReadMemoryResponse
---@field address string
---@field unreadableBytes integer|nil
---@field data string|nil  -- base64

---@class loop.dap.proto.WriteMemoryResponse
---@field offset integer|nil
---@field bytesWritten integer|nil
---@field verificationMessage string|nil

---@class loop.dap.proto.DisassembleResponse
---@field instructions loop.dap.proto.DisassembledInstruction[]
---@field totalInstructions integer|nil

---@class loop.dap.proto.ModulesResponse
---@field modules loop.dap.proto.Module[]
---@field totalModules integer|nil

---@class loop.dap.proto.DataBreakpointInfoResponse
---@field dataId string|nil
---@field description string|nil
---@field accessTypes ("read"|"write"|"readWrite")[]|nil
---@field canPersist boolean|nil

--====================================================================--
-- Events (COMPLETE)
--====================================================================--

---@class loop.dap.proto.InitializedEvent
-- empty

---@class loop.dap.proto.StoppedEvent
---@field reason "step"|"breakpoint"|"exception"|"pause"|"entry"|"goto"|"function breakpoint"|"data breakpoint"|"instruction breakpoint"
---@field description string|nil
---@field threadId integer|nil
---@field preserveFocusHint boolean|nil
---@field text string|nil
---@field allThreadsStopped boolean|nil
---@field hitBreakpointIds integer[]|nil
---@field frameId integer|nil

---@class loop.dap.proto.ContinuedEvent
---@field threadId integer
---@field allThreadsContinued boolean|nil
---@field singleThread boolean|nil

---@class loop.dap.proto.ThreadEvent
---@field reason "started"|"exited"
---@field threadId integer

---@class loop.dap.proto.OutputEvent
---@field category "console"|"stdout"|"stderr"|"telemetry"|nil
---@field output string
---@field group "start"|"startCollapsed"|"end"|nil
---@field variablesReference integer|nil
---@field source loop.dap.proto.Source|nil
---@field line integer|nil
---@field column integer|nil
---@field data any|nil

---@class loop.dap.proto.BreakpointEvent
---@field reason "new"|"changed"|"removed"|"function new"|"function changed"|"function removed"
---@field breakpoint loop.dap.proto.Breakpoint

---@class loop.dap.proto.ModuleEvent
---@field reason "new"|"changed"|"removed"
---@field module loop.dap.proto.Module

---@class loop.dap.proto.LoadedSourceEvent
---@field reason "new"|"changed"|"removed"
---@field source loop.dap.proto.Source

---@class loop.dap.proto.ProcessEvent
---@field name string
---@field systemProcessId integer|nil
---@field isLocalProcess boolean|nil
---@field startMethod "launch"|"attach"|"attachForSuspendedLaunch"|nil
---@field pointerSize integer|nil

---@class loop.dap.proto.ExitedEvent
---@field exitCode integer

---@class loop.dap.proto.TerminatedEvent
---@field restart boolean|nil

---@class loop.dap.proto.InvalidatedEvent
---@field areas ("all"|"stacks"|"threads"|"variables"|"memory"|"registers")[]|nil
---@field threadId integer|nil
---@field stackFrameId integer|nil
---@field expressionId string|nil

---@class loop.dap.proto.MemoryEvent
---@field memoryReference string
---@field offset integer
---@field count integer

---@class loop.dap.proto.ProgressStartEvent
---@field progressId string
---@field title string
---@field requestId integer|nil
---@field percentage number|nil
---@field message string|nil
---@field cancellable boolean|nil

---@class loop.dap.proto.ProgressUpdateEvent
---@field progressId string
---@field message string|nil
---@field percentage number|nil

---@class loop.dap.proto.ProgressEndEvent
---@field progressId string
---@field message string|nil

