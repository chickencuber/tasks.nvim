local M = {};
---@return string
local function create_id()
    local now = os.time()
    local d = os.date("!*t")
    --HACK branch impossible, just here to make the lsp happy
    if type(d) ~= "string" then
        local utc = os.time(d)
        local offset = os.difftime(now, utc) / 3600
        local date = os.date("%Y%m%d-%H%M%S")
        local offset_str
        if offset < 0 then
            offset_str = ("n%d"):format(-offset)
        elseif offset > 0 then
            offset_str = ("p%d"):format(offset)
        else
            offset_str = "00"
        end
        local millis = math.floor(select(2, vim.uv.gettimeofday()) / 1000)
        -- random to prevent possible collisions
        local id = ("%s-%03d-%s-%03d"):format(date, millis,offset_str, math.random(0, 999))
        return id
    end
    return ""
end

---@return string|nil
local function find_path()
    local root = vim.loop.os_uname().version:match("^Windows") and "C:\\" or "/"
    local dir = vim.fn.expand("%:p:h")
    while dir ~= root do
        local t = vim.fs.joinpath(dir, ".tasks")
        if vim.fn.isdirectory(t) == 1 then
            return t;
        end
        dir = vim.fs.dirname(dir)
    end
    return nil
end

--TASK(20251205-215429-416-n6-936): add better error handling
function M.setup(opts)
    opts = opts or {}
    local cwdfn = opts.cwdfn or function ()
        return vim.fn.getcwd()
    end
    local cmd = opts.cmd or "split"
    local hide = true
    if opts.hide ~= nil then
        hide = opts.hide
    end

    vim.api.nvim_create_user_command("TaskGoto", function()
        local line = vim.api.nvim_get_current_line()
        local _, col = unpack(vim.api.nvim_win_get_cursor(0))
        col = col + 1

        local reg = [[TASK%((..........................)%)]]
        local s, e, id = line:find(reg)

        if s and e then
            if col >= s and col <= e then
                local path = find_path()
                local file = vim.fs.joinpath(path, ("%s.md"):format(id))
                if vim.uv.fs_stat(file) ~= nil then
                    vim.cmd(("%s %s"):format(cmd,file))
                    if hide then
                        vim.api.nvim_set_option_value("bufhidden", "wipe", {
                            buf = 0
                        })
                    end
                end
            end
        end
    end, {})

    vim.api.nvim_create_user_command('TaskInit', function(_)
        local cwd = cwdfn()
        vim.fn.mkdir(vim.fs.joinpath(cwd, ".tasks"))
    end, {})
    vim.api.nvim_create_user_command("TaskFromTodo", function(_)
        local line = vim.api.nvim_get_current_line()
        local reg = ([[(%%s*%s%%s*)TODO (.*)]]):format(
            vim.bo.commentstring:format(""):gsub("^%s+", ""):gsub("%s+$", "")
        );
        local prefix, suffix = line:match(reg)
        if prefix and suffix then
            local path = find_path()
            if path then
                local id = create_id()
                local file = vim.fs.joinpath(path, ("%s.md"):format(id))
                vim.fn.writefile({
                    ("# TODO: %s"):format(suffix),
                    "",
                    "- OPEN",
                }, file)
                local row = vim.api.nvim_win_get_cursor(0)[1]
                vim.api.nvim_buf_set_lines(0, row-1, row, false, {
                    ("%sTASK(%s): %s"):format(
                        prefix, id, suffix
                    )
                })
                vim.cmd(("%s %s"):format(cmd,file))
                if hide then
                    vim.api.nvim_set_option_value("bufhidden", "wipe", {
                        buf = 0
                    })
                end
            end
        end
    end, {})
end

return M;
