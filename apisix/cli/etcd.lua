--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local base64_encode = require("base64").encode
local dkjson = require("dkjson")
local constants = require("apisix.constants")
local util = require("apisix.cli.util")
local file = require("apisix.cli.file")
local http = require("socket.http")
local https = require("ssl.https")
local ltn12 = require("ltn12")

local type = type
local ipairs = ipairs
local pairs = pairs
local print = print
local tonumber = tonumber
local str_format = string.format
local str_sub = string.sub
local table_concat = table.concat
local table_insert = table.insert
local io_stderr = io.stderr

local _M = {}

-- Timeout for all I/O operations
http.TIMEOUT = 3

local function parse_semantic_version(ver)
    local errmsg = "invalid semantic version: " .. ver

    local parts = util.split(ver, "-")
    if #parts > 2 then
        return nil, errmsg
    end

    if #parts == 2 then
        ver = parts[1]
    end

    local fields = util.split(ver, ".")
    if #fields ~= 3 then
        return nil, errmsg
    end

    local major = tonumber(fields[1])
    local minor = tonumber(fields[2])
    local patch = tonumber(fields[3])

    if not (major and minor and patch) then
        return nil, errmsg
    end

    return {
        major = major,
        minor = minor,
        patch = patch,
    }
end


local function compare_semantic_version(v1, v2)
    local ver1, err = parse_semantic_version(v1)
    if not ver1 then
        return nil, err
    end

    local ver2, err = parse_semantic_version(v2)
    if not ver2 then
        return nil, err
    end

    if ver1.major ~= ver2.major then
        return ver1.major < ver2.major
    end

    if ver1.minor ~= ver2.minor then
        return ver1.minor < ver2.minor
    end

    return ver1.patch < ver2.patch
end


local function request(url, yaml_conf)
    local response_body = {}
    local single_request = false
    if type(url) == "string" then
        url = {
            url = url,
            method = "GET",
            sink = ltn12.sink.table(response_body),
        }
        single_request = true
    end

    local res, code

    if str_sub(url.url, 1, 8) == "https://" then
        local verify = "peer"
        if yaml_conf.etcd.tls then
            local cfg = yaml_conf.etcd.tls

            if cfg.verify == false then
                verify = "none"
            end

            url.certificate = cfg.cert
            url.key = cfg.key

            local apisix_ssl = yaml_conf.apisix.ssl
            if apisix_ssl and apisix_ssl.ssl_trusted_certificate then
                url.cafile = apisix_ssl.ssl_trusted_certificate
            end
        end

        url.verify = verify
        res, code = https.request(url)
    else

        res, code = http.request(url)
    end

    -- In case of failure, request returns nil followed by an error message.
    -- Else the first return value is the response body
    -- and followed by the response status code.
    if single_request and res ~= nil then
        return table_concat(response_body), code
    end

    return res, code
end


function _M.init(env, args)
    -- read_yaml_conf
    local yaml_conf, err = file.read_yaml_conf(env.apisix_home)
    if not yaml_conf then
        util.die("failed to read local yaml config of apisix: ", err)
    end

    if not yaml_conf.apisix then
        util.die("failed to read `apisix` field from yaml file when init etcd")
    end

    if yaml_conf.apisix.config_center ~= "etcd" then
        return true
    end

    if not yaml_conf.etcd then
        util.die("failed to read `etcd` field from yaml file when init etcd")
    end

    local etcd_conf = yaml_conf.etcd

    -- convert old single etcd config to multiple etcd config
    if type(yaml_conf.etcd.host) == "string" then
        yaml_conf.etcd.host = {yaml_conf.etcd.host}
    end

    local host_count = #(yaml_conf.etcd.host)
    local scheme
    for i = 1, host_count do
        local host = yaml_conf.etcd.host[i]
        local fields = util.split(host, "://")
        if not fields then
            util.die("malformed etcd endpoint: ", host, "\n")
        end

        if not scheme then
            scheme = fields[1]
        elseif scheme ~= fields[1] then
            print([[WARNING: mixed protocols among etcd endpoints]])
        end
    end

    -- check the etcd cluster version
    local etcd_healthy_hosts = {}
    for index, host in ipairs(yaml_conf.etcd.host) do
        table_insert(etcd_healthy_hosts, host)
    end
    print("etcd_healthy_hosts list ", etcd_healthy_hosts)
    if #etcd_healthy_hosts <= 0 then
        util.die("all etcd nodes are unavailable\n")
    end

    if (#etcd_healthy_hosts / host_count * 100) <= 50 then
        util.die("the etcd cluster needs at least 50% and above healthy nodes\n")
    end

    print("etcd_healthy_check pass ")
end


return _M
