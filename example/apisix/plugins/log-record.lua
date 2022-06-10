

local plugin_name = "log-record"

local schema = {
    type = "object",
    properties = {
        body = {
            description = "body to replace response.",
            type = "string"
        },
    },
    required = {"body"},
}

local _M = {
    version = 0.1,
    priority = 13,
    name = plugin_name,
    schema = schema,
}


function _M.access(conf, ctx)
    return 200, conf.body
end


return _M