local ffi = require("ffi")
local C = ffi.C
local utils = require("cmp_luarime.utils")

local IsNULL = utils.IsNULL
local IsFalse = utils.IsFalse
local IsEmpty = utils.IsEmpty()
local toString = utils.toString
local toBoolean = utils.toBoolean
local toBool = utils.toBool

local K_BackSpace = 0xff08
local K_PgUp = 0xff55
local K_PgDn = 0xff56

------------------------------------------------------------------------------

---@param ctype ffi.cdecl*|ffi.ctype*
---@param gc function|nil
---@return ffi.cdata*
local function StructCreate(ctype, gc)
    local ret = ffi.new(ctype)
    ffi.fill(ret, 0, ffi.sizeof(ctype))
    if gc then
        ret = ffi.gc(ret, gc)
    end
    return ret
end

---@param ctype ffi.cdecl*|ffi.ctype*
---@param gc function|nil
---@return ffi.cdata*
local function StructCreateInit(ctype, gc)
    local ret = StructCreate(ctype, gc)
    ret[0].data_size = ffi.sizeof(ctype) - ffi.sizeof("int")
    return ret
end

------------------------------------------------------------------------------
-- configuration -------------------------------------------------------------

local host = nil
local function gc_config(self)
    assert(host)
    host.config_close(self)
end

local mtRimeConfig = {
    __index = {
        bool = function(self, key, val)
            local api = host
            if type(val) == "nil" then
                return toBoolean(api.config_set_bool(self, key, val and C.True or C.False))
            else
                local value = ffi.new("Bool[1]", 0)
                local ret = toBoolean(api.config_get_bool(self, key, value))
                if ret then
                    return toBoolean(value[0])
                end
            end
        end,
        int = function(self, key, val)
            local api = host
            local config = StructCreate("RimeConfig[1]", gc_config)
            if val then
                return toBoolean(api.config_set_int(self, key, tonumber(val)))
            else
                local value = ffi.new("int[1]", 0)
                local ret = toBoolean(api.config_get_int(config, key, value))
                if ret then
                    return tonumber(value[0])
                end
            end
        end,
        double = function(self, key, val)
            local api = host
            local config = StructCreate("RimeConfig[1]", gc_config)
            if val then
                return toBoolean(api.config_set_double(self, key, tonumber(val)))
            else
                local value = ffi.new("double[1]", 0)
                local ret = toBoolean(api.config_get_double(config, key, value))
                if ret then
                    return tonumber(value[0])
                end
            end
        end,
        string = function(self, key, val)
            local api = host
            local config = StructCreate("RimeConfig[1]", gc_config)
            if val then
                return toBoolean(api.config_set_string(self, key, val))
            else
                local value = ffi.new("char[1024]", 0)
                local ret = toBoolean(api.config_get_string(config, key, value, ffi.sizeof(value) - 1))
                if ret then
                    return toString(value)
                end
            end
        end,
        item = function(self, key, val)
            local api = host
            if val then
                return toBoolean(api.config_set_item(self, key, val))
            else
                local value = StructCreate("RimeConfig[1]", gc_config)
                local ret = toBoolean(api.config_get_item(self, key, value))
                if ret then
                    return value
                end
            end
        end,
        ---@param signer string
        ---@return boolean
        updateSignature = function(self, signer)
            local api = host
            return toBoolean(api.config_update_signature(self, signer))
        end,
        ---@return boolean
        close = function(self)
            local api = host
            return toBoolean(api.config_close(self))
        end,
        ---@param key string
        ---@return boolean
        clear = function(self, key)
            local api = host
            return toBoolean(api.config_clear(self, key))
        end,
        ---@param key string
        ---@return number?
        size = function(self, key)
            local api = host
            return tonumber(api.config_list_size(self, key))
        end,
        ---@param key string
        ---@return boolean
        create_list = function(self, key)
            local api = host
            return toBoolean(api.config_create_list(self, key))
        end,
        ---@param key string
        ---@return boolean
        create_map = function(self, key)
            local api = host
            return toBoolean(api.config_create_map(self, key))
        end,
        iterator = function(self, key)
            local api = host
            local iter = StructCreate("RimeConfigIterator[1]", function(iter)
                api.config_end(iter)
            end)

            local size = tonumber(api.config_list_size(self, key))
            local ret = nil
            if size == 0 then
                ret = toBoolean(api.config_begin_map(iter, self, key))
            else
                ret = toBoolean(api.config_begin_list(iter, self, key))
            end

            if ret then
                iter = { iterator = iter }
                local function next(self, iter)
                    local b = toBoolean(api.config_next(iter.iterator))
                    if b then
                        iter.path = ffi.string(iter.iterator[0].path)
                        if size == 0 then
                            iter.key = ffi.string(iter.iterator[0].key)
                        else
                            iter.index = tonumber(iter.iterator[0].index)
                        end
                        return iter
                    else
                        iter = nil
                    end
                end
                return next, self, iter
            end
        end,
    },
}

-- session -------------------------------------------------------------------
-- menu help
---@menu RimeMenu
---@return table
local function Menu(menu)
    local ret = {}
    ret.page_size = menu.page_size
    ret.page_no = menu.page_no + 1 -- 按照lua 的习惯从1开始
    ret.is_last_page = toBoolean(menu.is_last_page)
    ret.highlighted_candidate_index = menu.highlighted_candidate_index + 1

    ret.num_candidates = menu.num_candidates
    local candidates = {}
    for i = 0, ret.num_candidates - 1 do
        table.insert(candidates, {
            text = toString(menu.candidates[i].text),
            comment = toString(menu.candidates[i].comment),
        })
    end
    ret.candidates = candidates

    if not IsNULL(menu.select_keys) then
        ret.select_keys = ffi.string(menu.select_keys)
    end
    return ret
end
-- composition help
---@return table
local function Composition(composition)
    local ret = {}
    ret.length = composition.length
    ret.cursor = composition.cursor_pos + 1
    ret.sel_start = composition.sel_start + 1
    ret.sel_end = composition.sel_end
    ret.preedit = composition.length > 0 and ffi.string(composition.preedit, ret.length) or nil
    return ret
end

-- session metatable
local mtSession = {
    __index = {
        exist = function(self)
            return toBoolean(self.api.find_session(self.id))
        end,
        destroy = function(self)
            if self.destroyed then
                return true
            end
            if toBoolean(self.api.find_session(self.id)) then
                self.destroyed = toBoolean(self.api.destroy_session(self.id))
            else
                self.destroyed = true
            end
            return self.destroyed
        end,
        -- testing -------------------------------------------------------------------
        ---@param key_sequence string
        simulate = function(self, key_sequence)
            return toBoolean(self.api.simulate_key_sequence(self.id, key_sequence))
        end,
        -- 处理按键
        ---@param mask integer
        ---@param keycode integer
        ---@return boolean
        process = function(self, keycode, mask)
            mask = mask or 0
            return toBoolean(self.api.process_key(self.id, keycode, mask))
        end,
        -- 判断是否有未提交的内容
        ---@return boolean true if there is unread commit text
        commit = function(self)
            return toBoolean(self.api.commit_composition(self.id))
        end,
        clear = function(self)
            self.api.clear_composition(self.id)
        end,

        -- 获取commit
        ---@return string|nil
        Commit = function(self)
            local commit = StructCreateInit("RimeCommit[1]")
            if toBoolean(self.api.get_commit(self.id, commit)) then
                return ffi.string(commit[0].text)
            end
        end,

        ---@return table|nil
        Status = function(self)
            local function totable(status)
                local ret = {}
                ret.schema_id = ffi.string(status.schema_id)
                ret.schema_name = ffi.string(status.schema_name)

                ret.disabled = toBoolean(status.is_disabled)
                ret.composing = toBoolean(status.is_composing)
                ret.ascii_mode = toBoolean(status.is_ascii_mode)
                ret.full_shape = toBoolean(status.is_full_shape)
                ret.simplified = toBoolean(status.is_simplified)

                return ret
            end

            local status = StructCreateInit("RimeStatus[1]", function(status)
                self.api.free_status(status)
            end)

            if toBoolean(self.api.get_status(self.id, status)) then
                return totable(status[0])
            end
        end,

        ---@return table|nil
        Context = function(self)
            local context = StructCreateInit("RimeContext[1]")
            if toBoolean(self.api.get_context(self.id, context)) then
                local ret = {
                    composition = Composition(context[0].composition),
                    menu = Menu(context[0].menu),
                }

                if not IsNULL(context[0].select_labels) then
                    local lables = {}
                    local i = 0
                    repeat
                        local l = context[0].select_labels[i]
                        if not IsNULL(l) then
                            lables[#lables + 1] = ffi.string(l)
                        end
                    until IsNULL(l)
                    ret.select_labels = lables
                end

                if not IsNULL(context[0].commit_text_preview) then
                    ret.commit_text_preview = ffi.string(context[0].commit_text_preview)
                end

                self.api.free_context(context)
                return ret
            end
        end,
        PageDown = function(self)
            local context = StructCreateInit("RimeContext[1]")
            if toBoolean(self.api.get_context(self.id, context)) then
                local menu = Menu(context[0].menu)
                if not menu.is_last_page then
                    self.api.process_key(self.id, K_PgDn, 0)
                else
                    return
                end
            end
        end,
        PageUp = function(self)
            local context = StructCreateInit("RimeContext[1]")
            if toBoolean(self.api.get_context(self.id, context)) then
                local menu = Menu(context[0].menu)
                if menu.page_no > 1 then
                    self.api.process_key(self.id, K_PgUp, 0)
                else
                    return
                end
            end
        end,

        ------------------------------------------------------------------------------
        --! get raw input
        --[[!
      *  NULL is returned if session does not exist.
      *  the returned pointer to input string will become invalid upon editing.
    --]]
        Input = function(self)
            return toString(self.api.get_input(self.id))
        end,

        --! if pos==nil, get caret posistion in terms of raw input
        --! or set caret posistion in terms of raw input
        ---@param pos integer|nil
        ---@return integer|nil
        CaretPos = function(self, pos)
            if pos == nil then
                return tonumber(self.api.get_caret_pos(self.id)) + 1
            else
                assert(pos > 0)
                self.api.set_caret_pos(self.id, pos - 1)
            end
        end,

        --! if full is true, select a candidate at the given index in candidate list.
        --! or select a candidate from current page.
        ---@param index integer
        ---@param full boolean
        ---@return boolean
        Select = function(self, index, full)
            assert(index > 0)
            if full then
                return toBoolean(self.api.select_candidate(self.id, index - 1))
            else
                return toBoolean(self.api.select_candidate_on_current_page(self.id, index - 1))
            end
        end,

        --! access candidate list.
        Candidates = function(self)
            local iterator = StructCreate("RimeCandidateListIterator[1]", function(iter)
                self.api.candidate_list_end(iter)
            end)

            if toBoolean(self.api.candidate_list_begin(self.id, iterator)) then
                local lists = {}
                repeat
                    local more = toBoolean(self.api.candidate_list_next(iterator))
                    if more then
                        lists[iterator[0].index + 1] = {
                            text = toString(iterator[0].candidate.text),
                            comment = toString(iterator[0].candidate.comment),
                        }
                    end
                until not more
                return lists
            end
        end,
        ---@param prop string
        ---@param value string|nil if nil then get_property else set_property
        Property = function(self, prop, value)
            if value == nil then
                local val = ffi.new("char[1024]", 0)
                local ret = toBoolean(self.api.get_property(self.id, prop, val, ffi.sizeof(val) - 1))
                if ret then
                    return toString(val)
                end
                return nil
            else
                assert(type(value) == "string")
                self.api.set_property(self.id, prop, value)
            end
        end,

        ---@param schema_id string|nil
        ---@return boolean|string?
        Schema = function(self, schema_id)
            if schema_id == nil then
                local current = ffi.new("char[256]", 0)
                if toBoolean(self.api.get_current_schema(self.id, current, ffi.sizeof(current) - 1)) then
                    return ffi.string(current)
                end
            else
                return toBoolean(self.api.select_schema(self.id, schema_id))
            end
        end,
    },
    __gc = function(self)
        if self.destroyed then
            return true
        end
        if toBoolean(self.api.find_session(self.id)) then
            self.destroyed = toBoolean(self.api.destroy_session(self.id))
        else
            self.destroyed = true
        end
        return self.destroyed
    end,
}
-- lua table转换成rime的traits
---@param traits_opts table
---@return RimeTraits
local toTraits = function(traits_opts)
    local traits = StructCreateInit("RimeTraits[1]")
    traits[0].shared_data_dir = traits_opts.shared_data_dir
    traits[0].user_data_dir = traits_opts.user_data_dir
    traits[0].log_dir = traits_opts.log_dir

    traits[0].distribution_name = traits_opts.distribution_name
    traits[0].distribution_code_name = traits_opts.distribution_code_name
    traits[0].distribution_version = traits_opts.distribution_version
    traits[0].app_name = traits_opts.app_name

    traits[0].min_log_level = traits_opts.min_log_level

    return traits
end

--IME metatable
local mtIME = {
    __index = {
        -- librime 初始化
        ---@param traits_tbl table
        ---@param fullcheck boolean
        ---@param on_message function|nil
        initialize = function(self, traits_tbl, fullcheck, on_message)
            self.traits = toTraits(traits_tbl)

            local api = self.api
            fullcheck = toBool(fullcheck)
            assert(self.traits)

            api.setup(self.traits)

            on_message = on_message
                or function(context_object, session_id, message_type, message_value)
                    local msg = string.format(
                        "message: [%d] [%s] %s\n",
                        tonumber(session_id),
                        toString(message_type),
                        toString(message_value)
                    )
                    print(msg)
                end
            api.set_notification_handler(on_message, nil)

            api.initialize(self.traits)
            if self.api.start_maintenance(fullcheck) then
                api.join_maintenance_thread()
            end
            self.initialized = true
            return true
        end,
        -- librime 释放进程
        finalize = function(self)
            if self.initlized then
                self.api.finalize()
            end
        end,

        ---@param full_check boolean
        ---@return boolean
        start_maintenance = function(self, full_check)
            return toBoolean(self.api.start_maintenance(toBool(full_check)))
        end,
        is_maintenance_mode = function(self)
            return toBoolean(self.api.is_maintenance_mode())
        end,
        join_maintenance_thread = function(self)
            self.api.join_maintenance_thread()
        end,

        --session management
        SessionCreate = function(self)
            local id = self.api.create_session()
            if id ~= 0 then
                return setmetatable({ id = id, api = self.api }, mtSession)
            end
        end,
        ---@param all boolean
        SessionCleanup = function(self, all)
            if not all then
                self.api.cleanup_stale_sessions()
            else
                self.api.cleanup_all_sessions()
            end
        end,

        -- 修改过配置文件之后进行部署
        ---@param traits RimeTraits
        deployer_initialize = function(self, traits)
            self.api.deployer_initialize(traits)
        end,
        ---@return boolean
        prebuild = function(self)
            return toBoolean(self.api.prebuild())
        end,
        ---@return boolean
        deploy = function(self)
            return toBoolean(self.api.deploy())
        end,
        ---@param schema_file string
        deploy_schema = function(self, schema_file)
            return toBoolean(self.api.deploy_schema(schema_file))
        end,
        ---@param file_name string
        ---@param version_key string
        ---@return boolean
        deploy_config_file = function(self, file_name, version_key)
            return toBoolean(self.api.deploy_config_file(file_name, version_key))
        end,
        ---@return boolean
        sync_user_data = function(self)
            return toBoolean(self.api.sync_user_data())
        end,

        --get all schema support
        ---@return RimeSchemaList
        Schemas = function(self)
            local api = self.api
            local schemas = StructCreate("RimeSchemaList[1]", function(schemas)
                api.free_schema_list(schemas)
            end)

            if toBoolean(self.api.get_schema_list(schemas)) then
                local ret = {}
                for i = 0, tonumber(schemas[0].size) - 1 do
                    ret[#ret + 1] = {
                        schema_id = ffi.string(schemas[0].list[i].schema_id),
                        name = ffi.string(schemas[0].list[i].name),
                    }
                end
                return ret
            end
        end,

        -- rime config ---------------------------------------------------------------
        --! get the version of librime
        Version = function(self)
            return toString(self.api.get_version())
        end,
        SharedDataDir = function(self)
            return toString(self.api.get_shared_data_dir())
        end,
        UserDataDir = function(self)
            return toString(self.api.get_user_data_dir())
        end,
        SyncDir = function(self)
            return toString(self.api.get_sync_dir())
        end,
        UserId = function(self)
            return toString(self.api.get_user_id())
        end,
        UserDataSyncDir = function(self)
            local buff = ffi.new("char[256]", 0)
            return toString(self.api.get_user_data_sync_dir(buff, ffi.sizeof(buff) - 1))
        end,

        --config
        ------------------------------------------------------------------------------
        --runtime
        ---@param option string
        ---@param value string|nil if nil then get_option else set_option
        Option = function(self, option, value)
            if value == nil then
                return toBoolean(self.api.get_option(self.id, option))
            else
                self.api.set_option(self.id, option, toBool(value))
            end
        end,
        ConfigCreate = function(self, init)
            local config = StructCreate("RimeConfig[1]", gc_config)
            if init then
                local ret = toBoolean(self.api.config_init(config))
                if not ret then
                    return nil
                end
            end
            host = host or self.api
            return config
        end,

        ConfigOpen = function(self, config_id)
            local config = StructCreate("RimeConfig[1]", gc_config)
            local ret = toBoolean(self.api.config_open(config_id, config))
            if ret then
                host = host or self.api
                return config
            end
        end,

        SchemaOpen = function(self, schema_id)
            local config = StructCreate("RimeConfig[1]", gc_config)
            local ret = toBoolean(self.api.schema_open(schema_id, config))
            if ret then
                host = host or self.api
                return config
            end
        end,
    },
    __call = function(self, hpath, sopath)
        if self.initialized then
            return
        end

        local f = io.open(hpath)
        local ctx = f:read("*a")
        f:close()

        self.rime = ffi.load(sopath)
        ffi.cdef(ctx)
        self.api = self.rime.rime_get_api()

        RimeConfig = RimeConfig or ffi.metatype("RimeConfig", mtRimeConfig)

        return self
    end,
}

return setmetatable({
    initialized = false,
    traits = nil,
    session = nil,
}, mtIME)
