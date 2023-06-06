local db = require('annotate.db')
local M = {}

-- TODO: allow these window options to be configured?
-- TODO: should scrolling the parent win cause the annotation to disappear or remain anchored at line?
local function create_annot_win(annot_buf, cursor_ln, extmark_parent_win, win_width, padding)
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
        annot_win = create_annot_win(annot_buf, cursor_ln, extmark_parent_win, win_width, padding)
        vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
        print('Existing buffer + window don\'t exist: ', annot_buf, annot_win)
    else
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, true, {})
        annot_win = create_annot_win(annot_buf, cursor_ln, extmark_parent_win, win_width, padding)
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
local function set_buf_annotations(extmark_parent_buf)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
    if next(existing_extmarks) == nil then
        -- TODO: should these options just be set globally?
        local opts = {
            sign_text='󰍕',
            sign_hl_group = 'comment'
        }
        local extmark_tbl = db.get_all_annot(parent_buf_path)
        if next(extmark_tbl) == nil then
            print('No annotations exist for this file')
        else
            for _, row in ipairs(extmark_tbl) do
                vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, row['extmark_ln'], 0, opts)
            end
            existing_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
            print('Existing annotations set for bufnr: ', extmark_parent_buf)
        end
    else
        -- TODO: should there be additional functionality here?
        print('Annotations already set for bufnr: ', extmark_parent_buf)
    end
    return existing_extmarks
end

curr_extmarks = {}

local function monitor_buf(extmark_parent_buf)
    local ns = vim.api.nvim_create_namespace('annotate')
    vim.api.nvim_buf_attach(extmark_parent_buf, false, {
        on_lines = function(_, _, _, _, _)
            local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
            print('Callback fired from bufnr: ', extmark_parent_buf)
            print('Current extmarks:')
            print(vim.inspect(curr_extmarks))
            -- reminder that curr_extmark is like
            -- {[bufnr] = {{id, row, col}, {id, row, col}}, ...}
            vim.schedule(function()
                local mod_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
                -- for each extmark for current buf
                for i, extmark1 in ipairs(curr_extmarks[extmark_parent_buf]) do
                    local id1 = extmark1[1]
                    local ln1 = extmark1[2]
                    -- for each extmark in the latest list of entries
                    for _, extmark2 in ipairs(mod_extmarks) do
                        local id2 = extmark2[1]
                        local ln2 = extmark2[2]
                        if id1 == id2 and ln1 ~= ln2 then
                            -- print('Old:')
                            -- print(vim.inspect(curr_extmarks[extmark_parent_buf][i]))
                            -- print('New:')
                            -- print(vim.inspect(extmark2))
                            curr_extmarks[extmark_parent_buf][i] = extmark2
                            break
                        end
                    end
                    -- now flush to DB once extmark1 has completed its checking/updating
                    -- print('Replacing ', ln1)
                    -- print('with ', curr_extmarks[extmark_parent_buf][i][2])
                    db.updt_annot_pos(parent_buf_path, ln1, curr_extmarks[extmark_parent_buf][i][2])
                end
                print('Updated extmarks:')
                print(vim.inspect(curr_extmarks))
            end)
        end
    })
end

-- TODO: define autocommand here that will flush the contents of curr_extmark to DB?
-- reminder that curr_extmark is like
-- {[bufnr] = {{id, row, col}, {id, row, col}}, ...}
-- however, at that point we'd have no knowledge of which record in DB to update
-- so might have to do the DB at the point that we have the old position and use it as
-- the query condition
-- addtl benefit is that assumption of only one extmark per line guarantees we're always 
-- querying the correct record when using extmark_ln?
function M.set_annotations()
    local cwd = '^' .. vim.fn.getcwd()
    local buf_info = vim.fn.getbufinfo()
    for _, buf in ipairs(buf_info) do
        if string.match(buf.name, cwd) and vim.fn.bufexists(buf.bufnr) then
            curr_extmarks[buf.bufnr] = set_buf_annotations(buf.bufnr)
            monitor_buf(buf.bufnr)
        end
    end
end

-- TODO: delete this helper too
function M.list_annotations()
    local namespace = vim.api.nvim_create_namespace('annotate')
    local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    P(marks)
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
    -- TODO: use webdevicons as default or allow config?
    local opts = {
        sign_text = '󰍕',
        sign_hl_group = 'comment'
    }
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    -- TODO: fig out if mark_id is useful
    local mark_id
    local annot_buf
    local is_updt
    if next(existing_extmark) == nil then
        annot_buf, _ = create_annot_buf(cursor_ln)
        is_updt = false
        -- print('Creating new annotation')
    else
        mark_id = existing_extmark[1][1]
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        annot_buf, _ = create_annot_buf(cursor_ln)
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
        is_updt = true
        -- TODO: clean this up to use desired hl group, symbol, etc.
        vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
            id = mark_id,
            sign_text = '󰍕',
            sign_hl_group = 'Error'
        })
        -- print('Fetched existing annotation')
    end

    -- TODO: consider other/addtl events
    -- other events to consider:
    -- WinClosed, WinLeave (BufLeave is executed before it)
    -- TODO: saving to DB should only happen if the annotation buffer actually has mods --> vim.api.nvim_buf_attach()
    local au_group = vim.api.nvim_create_augroup('Annotate', {clear=true})
    vim.api.nvim_create_autocmd('BufHidden', {
        callback=function()
            local empty_lines = check_annot_buf_empty(annot_buf)
            local curr_mark
            if empty_lines then
                -- TODO: instead of denying, ask whether annotation should be deleted instead
                curr_mark = mark_id
                print('Annotation is empty')
            else
                -- TODO: only do DB operations after checking that the annotation has actually changed
                local buf_txt = vim.api.nvim_buf_get_lines(annot_buf, 0, -1, true)
                if is_updt then
                    db.updt_annot(parent_buf_path, cursor_ln, buf_txt)
                    curr_mark = mark_id
                    print('Modified annotation. is_updt: ', is_updt)
                else
                    curr_mark = vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, opts)
                    db.create_annot(parent_buf_path, cursor_ln, buf_txt)
                    print('Created new annotation. is_updt: ', is_updt)
                end
            end
            -- TODO: clean this up too
            vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
                id = curr_mark,
                sign_text = '󰍕',
                sign_hl_group = 'comment'
            })
        end,
        group=au_group,
        buffer=annot_buf
    })
end

function M.delete_annotation()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    local mark_id

    if next(existing_extmark) == nil then
        print('No existing extmark here')
    else
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        local annot_buf, annot_win = create_annot_buf(cursor_ln)
        mark_id = existing_extmark[1][1]
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
        -- TODO: clean this up too
        vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
            id = mark_id,
            sign_text = '󰍕',
            sign_hl_group = 'Error'
        })

        -- TODO: I *think* this is proper use of vim.schedule? intent: schedule prompt for after window shown
        vim.schedule(function()
            local confirm = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
            if confirm:lower() == 'y' then
                -- local mark_id = existing_extmark[1][1]
                vim.api.nvim_buf_del_extmark(extmark_parent_buf, ns, mark_id)
                db.del_annot(parent_buf_path, cursor_ln)
                print('Deleted successfully')
                -- TODO: this seems to trigger the BufHidden autocmd and deletion doesn't happen correctly
                -- trying just deleting the autogroup...should be restored by create func?
                -- other option that seems to work is vim.cmd('noautocmd') to disable autocmds for one command
                -- unsure how pecific though, so side-effects?
                vim.api.nvim_del_augroup_by_name('Annotate')
                -- vim.cmd('noautocmd')
                vim.api.nvim_win_hide(annot_win)
            else
                print('Annotation NOT deleted')
            end
        end)
    end
end

return M
