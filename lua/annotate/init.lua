local db = require('annotate.db')
local M = {}

function M.list_annotations()
    local namespace = vim.api.nvim_create_namespace('annotate')
    local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    P(marks)
end


local create_annot_buf = function(cursor_ln)
    local bufnr = vim.api.nvim_create_buf(false, true) -- unlisted scratch-buffer
    -- vim.api.nvim_set_option_value('wrap', true, {buf=bufnr})
    local win_parent = vim.api.nvim_get_current_win()
    local win_width = vim.api.nvim_win_get_width(win_parent)
    local padding = 2
    -- returns a window handle:
    -- TODO: tune these settings or make them configurable
    -- TODO: consider wrapping behavior? setting a fixed textwidth?
    local win_float = vim.api.nvim_open_win(bufnr, true, {
        relative = 'win',
        win = win_parent,
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
    vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
    return bufnr
end



local au_group = vim.api.nvim_create_augroup('annotations', {clear=true})
local function send_annot(buf, cursor_ln)
    local buf_txt = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    db.create_annot(cursor_ln + 1, buf_txt)
end

-- TODO: put the floating window stuff in a helper func if it can be used elsewhere
function M.set_annotation()
    local cursor_ln = vim.api.nvim_win_get_cursor(0)[1] - 1 -- 1-based lines conv to 0-based for extmarks
    local ns = vim.api.nvim_create_namespace('annotate')
    local opts = {
        sign_text='󰍕'
    }
    -- extmarks on this line
    -- uses 0-based indices for extmark location
    local existing_extmark = vim.api.nvim_buf_get_extmarks(0, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    -- TODO: fig out if we need mark_id?
    local mark_id
    if next(existing_extmark) == nil then
        mark_id = vim.api.nvim_buf_set_extmark(0, ns, cursor_ln, 0, opts)
        local bufnr = create_annot_buf(cursor_ln)
        vim.api.nvim_create_autocmd('BufLeave', {
            callback=function() print('Save extmark line as ' .. cursor_ln) end,
            group=au_group,
            buffer=bufnr
        })
    else
        mark_id = existing_extmark[1][1]
        -- TODO: create floating window and populate with current annotation from DB
        -- can use vim.api.nvim_buf_set_lines() to set the text
        print('Fetching annotation...')
    end
end

function M.delete_annotation()
    local cursor_ln = cursor_loc()
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmarks = vim.api.nvim_buf_get_extmarks(0, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    if next(existing_extmarks) == nil then
        -- error('No existing extmark here')
        print('No existing extmark here')
    else
        local confirm = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
        if confirm:lower() == 'y' then
            local mark_id = existing_extmarks[1][1]
            vim.api.nvim_buf_del_extmark(0, ns, mark_id)
            -- the call to DB should happen here
        else
            vim.cmd('redraw')
            print('Annotation NOT deleted')
        end
    end
end

return M
