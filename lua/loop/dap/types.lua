-- dap-types.lua
-- Full Debug Adapter Protocol (DAP) types for EmmyLua LSP
-- Based on official DAP specification: https://microsoft.github.io/debug-adapter-protocol/specification

---@meta

---@alias DAP.Sequence integer
---@alias DAP.RequestSeq integer

--====================================================================--
-- Common Types
--====================================================================--

---@class DAP.ProtocolMessage
---@field seq DAP.Sequence
---@field type '"request"' | '"response"' | '"event"'

---@class DAP.Request : DAP.ProtocolMessage
---@field type '"request"'
---@field command string
---@field arguments? table

---@class DAP.Response : DAP.ProtocolMessage
---@field type '"response"'
---@field request_seq DAP.RequestSeq
---@field success boolean
---@field command string
---@field message? string
---@field body? table

---@class DAP.Event : DAP.ProtocolMessage
---@field type '"event"'
---@field event string
---@field body? table

--====================================================================--
-- Common Shared Types
--====================================================================--

---@class DAP.Source
---@field name? string
---@field path? string
---@field sourceReference? integer
---@field presentationHint? '"normal"' | '"emphasize"' | '"deemphasize"'
---@field origin? string
---@field sources? DAP.Source[]
---@field adapterData? any
---@field checksums? { algorithm: string, checksum: string }[]

---@class DAP.SourceBreakpoint
---@field line integer
---@field column? integer
---@field condition? string
---@field hitCondition? string
---@field logMessage? string

---@class DAP.StackFrame
---@field id integer
---@field name string
---@field source? DAP.Source
---@field line integer
---@field column integer
---@field endLine? integer
---@field endColumn? integer
---@field presentationHint? '"normal"' | '"label"' | '"subtle"'

---@class DAP.Thread
---@field id integer
---@field name string

---@class DAP.Scope
---@field name string
---@field presentationHint? '"arguments"' | '"locals"' | '"registers"'
---@field variablesReference integer
---@field namedVariables? integer
---@field indexedVariables? integer
---@field expensive boolean
---@field source? DAP.Source
---@field line? integer
---@field column? integer
---@field endLine? integer
---@field endColumn? integer

---@class DAP.Variable
---@field name string
---@field value string
---@field type? string
---@field presentationHint? { kind?: '"property"'|'"method"'|'"class"'|'"data"'|'"event"'|'"baseClass"'|'"innerClass"'|'"interface"'|'"mostDerivedClass"'|'"virtual"'|'"data"', visibility?: '"public"'|'"private"'|'"protected"'|'"internal"'|'"final"', lazy?: boolean }
---@field evaluateName? string
---@field variablesReference integer
---@field namedVariables? integer
---@field indexedVariables? integer
---@field memoryReference? string

--====================================================================--
-- Requests & Responses (only bodies shown where needed)
--====================================================================--

---@class DAP.InitializeRequestArguments
---@field clientID? string
---@field clientName? string
---@field adapterID string
---@field locale? string
---@field linesStartAt1 boolean
---@field columnsStartAt1 boolean
---@field pathFormat '"path"' | '"uri"'
---@field supportsVariableType? boolean
---@field supportsVariablePaging? boolean
---@field supportsRunInTerminalRequest? boolean
---@field supportsMemoryReferences? boolean
---@field supportsProgressReporting? boolean
---@field supportsInvalidatedEvent? boolean

---@class DAP.Capabilities : table
    -- Full list: https://microsoft.github.io/debug-adapter-protocol/specification
    -- Commonly used:
    local supportsConfigurationDoneRequest = true
    local supportsFunctionBreakpoints = true
    local supportsConditionalBreakpoints = true
    local supportsHitConditionalBreakpoints = true
    local supportsEvaluateForHovers = true
    local exceptionBreakpointFilters = true
    local supportsStepBack = true
    local supportsSetVariable = true
    local supportsRestartFrame = true
    local supportsGotoTargetsRequest = true
    local supportsStepInTargetsRequest = true
    local supportsCompletionsRequest = true
    local supportsModulesRequest = true
    local additionalModuleColumns = true
    local supportedChecksumAlgorithms = true
    local supportsExceptionOptions = true
    local supportsValueFormattingOptions = true
    local supportsExceptionInfoRequest = true
    local supportTerminateDebuggee = true
    local supportSuspendDebuggee = true
    local supportsDelayedStackTraceLoading = true
    local supportsLoadedSourcesRequest = true
    local supportsLogPoints = true
    local supportsTerminateThreadsRequest = true
    local supportsSetExpression = true
    local supportsTerminateRequest = true
    local supportsDataBreakpoints = true
    local supportsReadMemoryRequest = true
    local supportsWriteMemoryRequest = true
    local supportsDisassembleRequest = true
    local supportsCancelRequest = true
    local supportsBreakpointLocationsRequest = true
    local supportsClipboardContext = true
    local supportsSteppingGranularity = true
    local supportsInstructionBreakpoints = true
    local supportsExceptionFilterOptions = true

---@class DAP.LaunchRequestArguments : table
---@class DAP.AttachRequestArguments : table

---@class DAP.SetBreakpointsArguments
---@field source DAP.Source
---@field breakpoints? DAP.SourceBreakpoint[]
---@field lines? integer[]
---@field sourceModified? boolean

---@class DAP.SetBreakpointsResponseBody
---@field breakpoints { verified: boolean, id?: integer, line?: integer, column?: integer, endLine?: integer, endColumn?: integer, message?: string, source?: DAP.Source }[]

---@class DAP.ThreadsResponseBody
---@field threads DAP.Thread[]

---@class DAP.StackTraceArguments
---@field threadId integer
---@field startFrame? integer
---@field levels? integer
---@field format? { module?: boolean, parameters?: boolean, parameterTypes?: boolean, parameterNames?: boolean, parameterValues?: boolean, line?: boolean, hex?: boolean }

---@class DAP.StackTraceResponseBody
---@field stackFrames DAP.StackFrame[]
---@field totalFrames? integer

---@class DAP.ScopesArguments
---@field frameId integer

---@class DAP.ScopesResponseBody
---@field scopes DAP.Scope[]

---@class DAP.VariablesArguments
---@field variablesReference integer
---@field filter? '"indexed"' | '"named"'
---@field start? integer
---@field count? integer
---@field format? { hex: boolean }

---@class DAP.VariablesResponseBody
---@field variables DAP.Variable[]

---@class DAP.ContinueArguments
---@field threadId integer

---@class DAP.ContinueResponseBody
---@field allThreadsContinued? boolean

---@class DAP.EvaluateArguments
---@field expression string
---@field frameId? integer
---@field context? '"watch"' | '"repl"' | '"hover"' | '"clipboard"'
---@field format? { hex: boolean }

---@class DAP.EvaluateResponseBody
---@field result string
---@field type? string
---@field presentationHint? DAP.Variable.presentationHint
---@field variablesReference integer
---@field namedVariables? integer
---@field indexedVariables? integer
---@field memoryReference? string

--====================================================================--
-- Events
--====================================================================--

---@class DAP.StoppedEventBody
---@field reason '"step"' | '"breakpoint"' | '"exception"' | '"pause"' | '"entry"' | '"goto"' | '"function breakpoint"' | '"data breakpoint"' | '"instruction breakpoint"'
---@field description? string
---@field threadId? integer
---@field text? string
---@field allThreadsStopped? boolean
---@field hitBreakpointIds? integer[]

---@class DAP.TerminatedEventBody
---@field restart? boolean

---@class DAP.OutputEventBody
---@field category? '"console"' | '"important"' | '"stdout"' | '"stderr"' | '"telemetry"'
---@field output string
---@field group? '"start"' | '"startCollapsed"' | '"end"'
---@field variablesReference? integer
---@field source? DAP.Source
---@field line? integer
---@field column? integer
---@field data? any

--====================================================================--
-- Reverse Requests (from adapter to client)
--====================================================================--

---@class DAP.RunInTerminalRequestArguments
---@field kind? '"integrated"' | '"external"'
---@field title? string
---@field cwd string
---@field args string[]
---@field env? table<string,string>
---@field waitOnExit? boolean

---@class DAP.RunInTerminalResponseBody
---@field processId? integer
---@field shellProcessId? integer