local db = require('annotate.db')
local M = {}

function M.list_annotations()
    local namespace = vim.api.nvim_create_namespace('annotate')
    local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    P(marks)
end

-- TODO: allow these window options to be configured?
local function create_annot_win(annot_buf, extmark_parent_win, cursor_ln, win_width, padding)
    local annot_win = vim.api.nvim_open_win(annot_buf, true, {
        relative = 'win',
        win = extmark_parent_win,
        anchor = 'NE',
        row = cursor_ln - 1,
        col = win_width - padding,
        width = 25,
        height = 10,
        border = 'rounded',
        style = 'minimal',
        title = 'Annotation',
        title_pos = 'center'
    })
    return annot_win
end

local function create_annot_buf(cursor_ln)
    local annot_buf_name = 'Annotation'
    local annot_buf = vim.fn.bufnr(annot_buf_name)
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local win_width = vim.api.nvim_win_get_width(extmark_parent_win)
    local padding = 2
    local annot_win
    if annot_buf == -1 then
        annot_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(annot_buf, annot_buf_name)
        annot_win = create_annot_win(annot_buf, extmark_parent_win, cursor_ln, win_width, padding)
        vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
        print('Existing buffer + window don\'t exist: ', annot_buf, annot_win)
    else
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, true, {})
        annot_win = create_annot_win(annot_buf, extmark_parent_win, cursor_ln, win_width, padding)
        vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
        print('Fetched existing buffer + window: ', annot_buf, annot_win)
    end
    return annot_buf, annot_win
end

-- TODO: test this gmatch with weirder cases?
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

-- TODO: only for debugging (remove when done)
function M.check_line()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    P(existing_extmark)
    print('Cursor @ ', cursor_ln + 1)
end

function M.create_annotation()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1 -- 1-based lines conv to 0-based for extmarks
    local ns = vim.api.nvim_create_namespace('annotate')
    local opts = {
        sign_text='󰍕'
    }
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    -- TODO: fig out if we need mark_id
    -- local mark_id
    local annot_buf
    local is_updt
    if next(existing_extmark) == nil then
        annot_buf, _ = create_annot_buf(cursor_ln)
        is_updt = false
        print('Creating new annotation')
    else
        -- mark_id = existing_extmark[1][1]
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        annot_buf, _ = create_annot_buf(cursor_ln)
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
        is_updt = true
        print('Fetched existing annotation')
    end

    -- TODO: prob better to track that buffer has been modified AND left insert mode; or something closing window?
    -- TODO: make sure this isn't behaving diff from expectations
    -- TODO: could clean it up too and stick in a function that we'd ref here
    local au_group = vim.api.nvim_create_augroup('Annotate', {clear=true})
    vim.api.nvim_create_autocmd('BufLeave', {
        callback=function()
            local empty_lines = check_annot_buf_empty(annot_buf)
            if empty_lines then
                -- TODO: instead of denying, ask whether annotation should be deleted instead
                print('Annotation is empty')
            else
                -- TODO: only do DB operations after checking that the annotation has actually changed
                local buf_txt = vim.api.nvim_buf_get_lines(annot_buf, 0, -1, true)
                if is_updt then
                    -- send_annot(parent_buf_path, annot_buf, cursor_ln, is_updt)
                    db.updt_annot(parent_buf_path, cursor_ln, buf_txt)
                    print('Modified annotation. is_updt: ', is_updt)
                else
                    vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, opts)
                    -- send_annot(parent_buf_path, annot_buf, cursor_ln, is_updt)
                    db.create_annot(parent_buf_path, cursor_ln, buf_txt)
                    print('Created new annotation. is_updt: ', is_updt)
                end
            end
        end,
        group=au_group,
        buffer=annot_buf
    })
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
                print('Annotation NOT deleted')
            end
        end)
    end
end

return M
