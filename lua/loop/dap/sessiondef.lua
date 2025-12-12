---@meta

---@class loop.dap.session.SourceBPData
---@field user_data loop.dap.SourceBreakpoint
---@field verified boolean
---@field dap_id number|nil

---@class loop.dap.session.SourceBreakpointsData
---@field by_location table<string, table<number, loop.dap.session.SourceBPData>>
---@field by_usr_id table<number, loop.dap.session.SourceBPData>
---@field by_dap_id table<number, loop.dap.session.SourceBPData>
---@field pending_files table<string,boolean>

---@class loop.dap.session.notify.Trace
---@field level nil|"warn"|"error"
---@field text string


---@class loop.dap.session.notify.BreakpointState
---@field breakpoint_id number
---@field verified boolean
---@field removed boolean|nil

---@alias loop.dap.session.notify.BreakpointsEvent loop.dap.session.notify.BreakpointState[]

---@class loop.dap.AdapterConfig
---@field adapter_id string
---@field type "executable"|"server"
---@field host string|nil
---@field port number|nil
---@field name string
---@field command string|string[]|nil
---@field env table<string,string>|nil
---@field cwd string|nil

---@alias loop.session.TrackerEvent
---|"trace"
---|"state"
---|"output"
---|"runInTerminal_request"
---|"threads_paused"
---|"threads_continued"
---|"breakpoints"
---|"debuggee_exit"
---|"subsession_request"
---@alias loop.session.Tracker fun(session:loop.dap.Session, event:loop.session.TrackerEvent, args:any)

---@class loop.dap.session.DebugArgs
---@field adapter      loop.dap.AdapterConfig
---@field request      "launch" | "attach"
---@field request_args  loop.dap.proto.AttachRequestArguments|loop.dap.proto.LaunchRequestArguments|nil
---@field launch_post_configure boolean|nil
---@field terminate_debuggee boolean|nil

---@class loop.dap.session.Args
---@field debug_args loop.dap.session.DebugArgs|nil
---@field tracker loop.session.Tracker
---@field exit_handler fun(code:number)

---@class loop.dap.session.notify.SubsessionRequest
---@field name string
---@field debug_args loop.dap.session.DebugArgs
---@field on_success fun(resp_body:any)
---@field on_failure fun(reason:string)

---@class loop.dap.session.notify.StateData
---@field state "initializing"|"starting"|"running"|"disconnecting"|"terminating"|"ended"

---@alias loop.dap.session.StackProvider fun(args:loop.dap.proto.StackTraceArguments, callback:fun(err:string|nil, data: loop.dap.proto.StackTraceResponse | nil))
---@alias loop.dap.session.ScopesProvider fun(args:loop.dap.proto.ScopesArguments, callback:fun(err:string|nil, data: loop.dap.proto.ScopesResponse | nil))
---@alias loop.dap.session.VariablesProvider fun(args:loop.dap.proto.VariablesArguments, callback:fun(err:string|nil, data: loop.dap.proto.VariablesResponse | nil))
---@alias loop.dap.session.EvaluateProvider fun(args:loop.dap.proto.EvaluateArguments, callback:fun(err:string|nil, data: loop.dap.proto.EvaluateResponse | nil))

---@class loop.dap.session.DataProvidersExpiry
---@field expired boolean

---@class loop.dap.session.DataProviders
---@field expiry_info loop.dap.session.DataProvidersExpiry
---@field stack_provider loop.dap.session.StackProvider
---@field scopes_provider loop.dap.session.ScopesProvider
---@field variables_provider loop.dap.session.VariablesProvider
---@field evaluate_provider loop.dap.session.EvaluateProvider

---@class loop.dap.session.notify.ThreadData
---@field thread_id number
---@field threads loop.dap.proto.Thread[]
---@field stack_provider loop.dap.session.StackProvider
---@field scopes_provider loop.dap.session.ScopesProvider
---@field variables_provider loop.dap.session.VariablesProvider
---@field evaluate_provider loop.dap.session.EvaluateProvider
