local async = require('plenary.async')
-- local tx, rx = async.control.channel.oneshot()
-- local channel = require('plenary.async.control.channel')
local db = require('annotate.db')
local M = {}

function M.list_annotations()
    local namespace = vim.api.nvim_create_namespace('annotate')
    local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    P(marks)
end

-- TODO: make this reuse a single scratch buffer?
-- and just return that one so it can be thrown around for use
local function create_annot_buf(cursor_ln)
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local win_width = vim.api.nvim_win_get_width(extmark_parent_win)
    local annot_buf = vim.api.nvim_create_buf(false, true) -- unlisted scratch-buffer
    local padding = 2
    -- TODO: tune these settings or make them configurable
    -- TODO: consider wrapping behavior? setting a fixed textwidth?
    local annot_win = vim.api.nvim_open_win(annot_buf, true, {
        relative = 'win',
        win = extmark_parent_win,
        anchor = 'NE',
        row = cursor_ln - 1,
        col = win_width - padding,
        width = 25,
        height = 20,
        border = 'rounded',
        style = 'minimal',
        title = 'Annotation',
        title_pos = 'center'
    })
    vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
    return annot_buf, annot_win
end

-- TODO: test this gmatch better
local function build_annot(annot_txt)
    local annot_lines = {}
    for line in string.gmatch(annot_txt .. '``', '([^``]*)``') do
        table.insert(annot_lines, line)
    end
    return annot_lines
end

local function check_annot_buf_empty(annot_buf)
    local buf_txt = vim.api.nvim_buf_get_lines(annot_buf, 0, -1, true)
    local empty_lines = true
    for _, line in ipairs(buf_txt) do
        if line ~= '' then
            empty_lines = false
            break
        end
    end
    return empty_lines
end

local function send_annot(parent_buf_path, annot_buf, cursor_ln, updt_flag)
    local buf_txt = vim.api.nvim_buf_get_lines(annot_buf, 0, -1, true)
    if updt_flag then
        db.updt_annot(parent_buf_path, cursor_ln, buf_txt)
    else
        db.create_annot(parent_buf_path, cursor_ln, buf_txt)
    end
end

-- local function disp_annot(parent_buf_path, cursor_ln)
--     local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
--     local annot_lines = build_annot(annot_txt)
--     local annot_buf, annot_win = create_annot_buf(cursor_ln)
--     vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
-- end

-- local function confirm_annot_del(parent_buf_path, cursor_ln)
--     local chan = vim.loop.new_channel()
--     async.void(function()
--         local input = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
--         chan.send(input)
--     end)()
--     async.void(function()
--         local input = chan.recv()
--         disp_annot(parent_buf_path, cursor_ln)
--     end)()
-- end

local au_group = vim.api.nvim_create_augroup('Annotate', {clear=true})

-- TODO: should this function be auto-called when the plugin is started?
function M.set_annotations()
    local extmark_parent_buf = vim.api.nvim_get_current_buf()
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
    if next(existing_extmark) == nil then
        local opts = {
            sign_text='󰍕'
        }
        local extmark_tbl = db.get_all_annot(parent_buf_path)
        for _, row in ipairs(extmark_tbl) do
            vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, row['extmark_ln'], 0, opts)
        end
        print('Existing extmarks set')
    else
        -- TODO: should there be additional functionality here?
        print('Extmarks already set')
    end
end

function M.create_annotation()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    -- TODO: is one of these clearly favorable?
    -- local extmark_parent_buf = vim.api.nvim_get_current_buf()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1 -- 1-based lines conv to 0-based for extmarks
    local ns = vim.api.nvim_create_namespace('annotate')
    local opts = {
        sign_text='󰍕'
    }
    -- uses 0-based indices for extmark location
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    -- TODO: fig out if we need mark_id?
    local mark_id
    if next(existing_extmark) == nil then
        local annot_buf, annot_win = create_annot_buf(cursor_ln)
        -- TODO: find a better event than BufLeave, which is too sensitive/general
        vim.api.nvim_create_autocmd('BufLeave', {
            callback=function()
                local empty_lines = check_annot_buf_empty(annot_buf)
                if empty_lines then
                    -- TODO: instead of just denying, ask whether the annotation should just be deleted?
                    print('Annotation is empty')
                else
                    mark_id = vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, opts)
                    send_annot(parent_buf_path, annot_buf, cursor_ln, false)
                    print('Annotation set')
                end
            end,
            group=au_group,
            buffer=annot_buf
        })
    else
        -- mark_id = existing_extmark[1][1]
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        local annot_buf, annot_win = create_annot_buf(cursor_ln)
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
        -- TODO: prob better to track that buffer has been modified AND left insert mode
        vim.api.nvim_create_autocmd('InsertLeave', {
            callback=function()
                local empty_lines = check_annot_buf_empty(annot_buf)
                if empty_lines then
                    -- TODO: instead of denying, ask whether annotation should be deleted instead
                    print('Annotation is empty')
                else
                    send_annot(parent_buf_path, annot_buf, cursor_ln, true)
                    print('Annotation updated')
                end
            end,
            group=au_group,
            buffer=annot_buf
        })
    end
end

function M.delete_annotation()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    -- TODO: same here, is  one better?
    -- local extmark_parent_buf = vim.api.nvim_get_current_buf()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    if next(existing_extmark) == nil then
        print('No existing extmark here')
    else
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        local annot_buf, annot_win = create_annot_buf(cursor_ln)
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)

        -- TODO: I *think* this is proper use of vim.schedule? intention is to schedule prompt for after window shown
        vim.schedule(function()
            local confirm = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
            if confirm:lower() == 'y' then
                local mark_id = existing_extmark[1][1]
                vim.api.nvim_buf_del_extmark(extmark_parent_buf, ns, mark_id)
                db.del_annot(parent_buf_path, cursor_ln)
                -- TODO: should this be a window deletion instead?
                vim.api.nvim_win_hide(annot_win)
            else
                vim.cmd('redraw')
                print('Annotation NOT deleted')
            end
        end)
    end
end

return M
