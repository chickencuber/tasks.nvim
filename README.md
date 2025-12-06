# Tasks.nvim
this is a work in progress plugin for nvim it adds a task system that is embeded in the code  
## Install(Lazy)
```lua
return {
    "chickencuber/tasks.nvim",
    opts = {
        --for default options 
    }
}

```
## Defualt Options
```lua
{
    cwdfn = function() return vim.fn.getcwd() end,
    cmd = "split", -- split | vslpit | edit
    hide = true, -- or false
}
```
## add keymaps
```lua
vim.keymap.set("n", "tf", vim.cmd.TaskFromTodo)
vim.keymap.set("n", "gt", vim.cmd.TaskGoto)

```
## Usage
- `:TaskInit` initializes the task directory in the cwd
- `:TaskFromTodo` takes a TODO comment(--TODO or //TODO), and turns it into a task 
- `:TaskGoto` sends you to the file of the task that is being referenced
