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
            offset_str = "p0"
        end
        local millis = math.floor(select(2, vim.uv.gettimeofday()) / 1000)
        -- random to prevent possible collisions
        local id = ("%s-%03d-%s-%03d"):format(date, millis,offset_str, math.random(0, 999))
        return id
    end
    return ""
end

local function get_default_clip_reg()
  local cb = vim.o.clipboard
  if cb:find("unnamedplus") then
    return "+"
  elseif cb:find("unnamed") then
    return '"'
  else
    return '"'
  end
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

local menu = false

---@return {id: string, title: string, status: string, file:string, extra:string[]}|nil
---@param file string
local function parse_task_file(file)
    local lines = vim.fn.readfile(file)
    if #lines < 3 then return nil end

    local title = lines[1]:match("^#%s*(.*)")
    local status = lines[3]:match("^%- (%w+)")
    local id = vim.fs.basename(file):gsub("%.md$", "")
    local extra = {}
    for i = 4, #lines do
        table.insert(extra, lines[i])
    end
    if title and status then
        return { id = id, title = title, status = status, file=file, extra = extra}
    end
    return nil
end

---@return {id: string, title: string, status: string, file: string, extra:string[]}[]|nil
---@param cwd string
---@param show_closed boolean
local function get_table(cwd, show_closed)
    local task_dir = vim.fs.joinpath(cwd, ".tasks")
    if vim.fn.isdirectory(task_dir) == 1 then

        local files = vim.fs.find(function(name)
            return name:match('.*%.md$')
        end, { limit = math.huge, type = 'file' , path = task_dir})

        local open_tasks = {}

        for _, f in ipairs(files) do
            local task = parse_task_file(f)
            if task and (task.status == "OPEN" or show_closed) then
                table.insert(open_tasks, task)
            end
        end
        return open_tasks
    else
        return nil
    end
end

--TASK(20251205-230155-330-n6-984): add menu to manage tasks

--TASK(20251205-230204-234-n6-128): add better error handling
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

    vim.api.nvim_create_user_command("TaskYank", function()
        local line = vim.api.nvim_get_current_line()
        local _, col = unpack(vim.api.nvim_win_get_cursor(0))
        col = col + 1

        local reg = ([[(TASK%(%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-%d%d%d%-[np]%d%-%d%d%d%))]])
        local s, e, full = line:find(reg)

        if s and e then
            if col >= s and col <= e then
                vim.fn.setreg(get_default_clip_reg(), full)
                print("Yanked " .. full)
                return
            end
        end
        print("No Tasks Found")
    end, {})

    vim.api.nvim_create_user_command("TaskMenu", function(args) -- see TASK(20251205-230155-330-n6-984)
        --TASK(20251207-200923-784-n6-168): add Title to the menu
        --TASK(20251206-001046-495-n6-030): make the Menu keybinds customizable
        if menu then
            return
        end
        local buf = vim.api.nvim_create_buf(false, true)
        local arg = args.args
        local show_closed = false
        if arg == "show_closed" then
            show_closed = true
        end
        local t= get_table(cwdfn(), show_closed)
        if t == nil then
            print("Task dir not found")
            return
        end
        local width = math.floor(vim.o.columns * 0.6)
        local height = math.floor(vim.o.lines * 0.4)
        local row = math.floor((vim.o.lines - height) / 2)
        local col = math.floor((vim.o.columns - width) / 2)
        local window = {
            style = "minimal",
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            border = "rounded",
            title="Tasks",
            title_pos = "center",
        }
        vim.api.nvim_open_win(buf, true, window)

        vim.api.nvim_create_autocmd("BufLeave", {
            buffer = buf,
            once = true,
            callback = function()
                if vim.api.nvim_buf_is_valid(buf) then
                    menu = false
                    vim.api.nvim_buf_delete(buf, { force = true })
                end
            end
        })
        vim.keymap.set("n", "dd", function()
            local i= vim.api.nvim_win_get_cursor(0)[1]
            local entry = t[i]
            local set = "CLOSED"
            if entry.status == "CLOSED" and show_closed then
                set = "OPEN"
            end
            vim.api.nvim_set_option_value("modifiable", true, {buf = buf})
            if show_closed then
                entry.status = set
                vim.api.nvim_buf_set_lines(buf, i-1, i, false, {
                    ("TASK(%s): %s: %s"):format(entry.id, entry.title, entry.status)
                })
            else
                table.remove(t, i)
                vim.api.nvim_buf_set_lines(0, i-1, i, false, {})
            end
            vim.api.nvim_set_option_value("modifiable", false, {buf = buf})
            vim.fn.writefile({
                ("# %s"):format(entry.title),
                "",
                ("- %s"):format(set),
                unpack(entry.extra)
            }, entry.file)
        end, { buffer = buf, noremap = true, silent = true })

        vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = buf,
            callback = function()
                local y = vim.api.nvim_win_get_cursor(0)[1]
                vim.api.nvim_win_set_cursor(0, { y, 0 })
            end,
        })

        vim.keymap.set("n", "y", function()
            local i= vim.api.nvim_win_get_cursor(0)[1]
            local text = ("TASK(%s)"):format(t[i].id);
            vim.fn.setreg(get_default_clip_reg(), text)
            print("Yanked " .. text)
        end, { buffer = buf, noremap = true, silent = true })

        vim.keymap.set("n", "q", function()
            vim.api.nvim_win_close(0, true)
            menu = false;
        end, { buffer = buf, noremap = true, silent = true })
        vim.keymap.set("n", "<Esc>", function()
            vim.api.nvim_win_close(0, true)
            menu = false;
        end, { buffer = buf, noremap = true, silent = true })
        menu = true
        for i, v in pairs(t) do
            if show_closed then
                vim.api.nvim_buf_set_lines(buf, i-1, i, false, {
                    ("TASK(%s): %s: %s"):format(v.id, v.title, v.status)
                })
            else
                vim.api.nvim_buf_set_lines(buf, i-1, i, false, {
                    ("TASK(%s): %s"):format(v.id, v.title)
                })
            end
        end
        vim.api.nvim_set_option_value("modifiable", false, {buf = buf})
    end, {
    nargs = "*"
})
    vim.api.nvim_create_user_command("TaskGoto", function()
        local line = vim.api.nvim_get_current_line()
        local _, col = unpack(vim.api.nvim_win_get_cursor(0))
        col = col + 1

        local reg = ([[TASK%((%d%d%d%d%d%d%d%d%-%d%d%d%d%d%d%-%d%d%d%-[np]%d%-%d%d%d)%)]])
        local s, e, id = line:find(reg)

        if s and e then
            if col >= s and col <= e then
                local path = find_path()
                if path == nil then
                    print("Task dir not found")
                    return
                end
                local file = vim.fs.joinpath(path, ("%s.md"):format(id))
                if vim.uv.fs_stat(file) ~= nil then
                    if menu then
                        vim.api.nvim_win_close(0, true)
                        menu = false
                    end
                    vim.cmd(("%s %s"):format(cmd,file))
                    if hide then
                        vim.api.nvim_set_option_value("bufhidden", "wipe", {
                            buf = 0
                        })
                    end
                    return
                else
                    print(("Task %s not found"):format(id))
                    return
                end
            end
        end
        print("No Tasks found")
    end, {})

    vim.api.nvim_create_user_command('TaskInit', function(_)
        local cwd = cwdfn()
        vim.fn.mkdir(vim.fs.joinpath(cwd, ".tasks"))
    end, {})
    vim.api.nvim_create_user_command("TaskFromTodo", function(_)
        --TASK(20251206-004408-812-n6-024): add support for block comments
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
                    ("# %s"):format(suffix),
                    "",
                    "- OPEN",
                    -- any extra details would go after this
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
            else
                print("Task dir not found")
            end
        else
            print("No TODO comment found")
        end
    end, {})
end

return M;
