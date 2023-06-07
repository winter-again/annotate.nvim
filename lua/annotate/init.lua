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
        width = M.config.annot_win_width,
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
    local padding = M.config.annot_win_padding
    local annot_win
    if annot_buf == -1 then
        annot_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(annot_buf, annot_buf_name)
        vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
        annot_win = create_annot_win(annot_buf, cursor_ln, extmark_parent_win, win_width, padding)
        -- print('Existing buffer + window don\'t exist: ', annot_buf, annot_win)
    else
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, true, {})
        vim.api.nvim_buf_set_keymap(annot_buf, 'n', 'q', ':close<CR>', {noremap=true, silent=true, nowait=true})
        annot_win = create_annot_win(annot_buf, cursor_ln, extmark_parent_win, win_width, padding)
        -- print('Fetched existing buffer + window: ', annot_buf, annot_win)
    end
    return annot_buf, annot_win
end

-- TODO: test this gmatch with weirder cases?
-- TODO: consider things like stripping leading/trailing whitespaces?
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

local function set_buf_annotations(extmark_parent_buf)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
    if next(existing_extmarks) == nil then
        local extmark_tbl = db.get_all_annot(parent_buf_path)
        if next(extmark_tbl) == nil then
            -- print('No annotations exist for this file')
        else
            local opts = {
                sign_text = M.config.annot_sign,
                sign_hl_group = M.config.annot_sign_hl
            }
            for _, row in ipairs(extmark_tbl) do
                vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, row.extmark_ln, 0, opts)
            end
            existing_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
            -- print('Existing annotations set for bufnr: ', extmark_parent_buf)
        end
    else
        -- TODO: should there be additional functionality here?
        -- print('Annotations already set for bufnr: ', extmark_parent_buf)
    end
    return existing_extmarks
end

local curr_extmarks = {}
local curr_extmark_bufs = {}

-- TODO: clean up and consider make it useable from M.delete_annotation() or if there's
-- a better way to do it
local function prompt_delete(extmark_parent_buf, extmark_id, extmark_ln)
    local ns = vim.api.nvim_create_namespace('annotate')
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local annot_txt = db.get_annot(parent_buf_path, extmark_ln)[1]['text']
    local annot_lines = build_annot(annot_txt)
    local annot_buf, annot_win = create_annot_buf(extmark_ln + 1)
    vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
    vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, extmark_ln + 1, 0, {
        id = extmark_id,
        sign_text = M.config.annot_sign,
        sign_hl_group = M.config.annot_sign_hl_current
    })
    -- TODO: I *think* this is proper use of vim.schedule? intent: schedule prompt for after window shown
    vim.schedule(function()
        local confirm = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
        if confirm:lower() == 'y' then
            -- local mark_id = existing_extmark[1][1]
            vim.api.nvim_buf_del_extmark(extmark_parent_buf, ns, extmark_id)
            db.del_annot(parent_buf_path, extmark_ln + 1)
            print('Deleted successfully')
            -- TODO: is this the right way of handling? Should only disable for the following command
            vim.cmd('noautocmd')
            vim.api.nvim_win_hide(annot_win)
        else
            print('Annotation NOT deleted')
        end
    end)
end

-- TODO: also check if monitoring bufs without extmarks and nothing created YET
local function monitor_buf(extmark_parent_buf)
    local ns = vim.api.nvim_create_namespace('annotate')
    local is_monitored_buf = false
    for bufnr, _ in pairs(curr_extmark_bufs) do
        if extmark_parent_buf == bufnr then
            is_monitored_buf = true
            break
        end
    end
    if not is_monitored_buf then
        local initial_line_ct = vim.api.nvim_buf_line_count(extmark_parent_buf)
        -- table.insert(curr_extmark_bufs, extmark_parent_buf)
        curr_extmark_bufs[extmark_parent_buf] = initial_line_ct
        print('Monitoring bufnr ', extmark_parent_buf, is_monitored_buf)
        -- print('Init line count: ', curr_extmark_bufs[extmark_parent_buf])
        vim.api.nvim_buf_attach(extmark_parent_buf, false, {
            on_lines = function(_, _, _, first_line, last_line)
                local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
                vim.schedule(function()
                    -- TODO: can I use nvim_buf_get_extmark_by_id() here instead to compare location?
                    local mod_extmarks = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, 0, -1, {})
                    for i, extmark1 in ipairs(curr_extmarks[extmark_parent_buf]) do
                        local id1 = extmark1[1]
                        local ln1 = extmark1[2]
                        for _, extmark2 in ipairs(mod_extmarks) do
                            local id2 = extmark2[1]
                            local ln2 = extmark2[2]
                            if id1 == id2 and ln1 ~= ln2 then
                                curr_extmarks[extmark_parent_buf][i] = extmark2
                                db.updt_annot_pos(parent_buf_path, ln1, ln2)
                                break
                            end
                        end
                    end
                    local latest_lines = vim.api.nvim_buf_line_count(extmark_parent_buf)
                    for bufnr, lines in pairs(curr_extmark_bufs) do
                        for i, extmark in ipairs(curr_extmarks[bufnr]) do
                            if latest_lines < lines and (extmark[2] >= first_line and extmark[2] <= last_line) then
                                print('A deletion happened in bufnr ', bufnr)
                                print('First line is ', first_line)
                                print('Last line is ', last_line)
                                print('Affected extmark is:')
                                print(vim.inspect(extmark))
                                -- TODO: prompt for deletion of the extmark and the annotation
                                -- currently not working likely because the prompt_delete function itself
                                -- involves schedule, which is probably pushing back that floating window
                                -- render?
                                -- prompt_delete(extmark_parent_buf, extmark[1], extmark[2])
                                vim.api.nvim_buf_del_extmark(extmark_parent_buf, ns, extmark[1])
                                db.del_annot(parent_buf_path, extmark[2])
                                table.remove(curr_extmarks[bufnr], i)
                                print('Deleted extmark + annotation from DB and curr_extmarks')
                            end
                        end
                    end
                    curr_extmark_bufs[extmark_parent_buf] = latest_lines
                    print('Line count: ', curr_extmark_bufs[extmark_parent_buf])
                end)
            end
        })
    else
        print('Already monitoring bufnr ', extmark_parent_buf, is_monitored_buf)
    end
end

-- TODO: do we want to trigger all of this when no annotations exist for buf?
local function set_annotations()
    local cwd = '^' .. vim.fn.getcwd()
    local buf_info = vim.fn.getbufinfo()
    for _, buf in ipairs(buf_info) do
        -- TODO: are these conditions the best to check?
        if string.match(buf.name, cwd) and vim.fn.bufexists(buf.bufnr) and buf.listed == 1 then
            curr_extmarks[buf.bufnr] = set_buf_annotations(buf.bufnr)
            monitor_buf(buf.bufnr)
        end
    end
end

function M.create_annotation()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local parent_buf_path = vim.api.nvim_buf_get_name(extmark_parent_buf)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    local mark_id
    local annot_buf
    local is_updt

    annot_buf, _ = create_annot_buf(cursor_ln)
    if next(existing_extmark) == nil then
        is_updt = false
    else
        mark_id = existing_extmark[1][1]
        local annot_txt = db.get_annot(parent_buf_path, cursor_ln)[1]['text']
        local annot_lines = build_annot(annot_txt)
        vim.api.nvim_buf_set_lines(annot_buf, 0, -1, false, annot_lines)
        vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
            id = mark_id,
            sign_text = M.config.annot_sign,
            sign_hl_group = M.config.annot_sign_hl_current
        })
        is_updt = true
    end

    -- handle for when user is done interacting with the annotation floating window
    -- TODO: consider other/addtl events depending on how user might interact with the floating window
    -- other events to consider: WinClosed, WinLeave (BufLeave is executed before it)
    local au_group_edit = vim.api.nvim_create_augroup('AnnotateEdit', {clear=true})
    vim.api.nvim_create_autocmd('BufHidden', {
        callback = function()
            local empty_lines = check_annot_buf_empty(annot_buf)
            local curr_mark
            if empty_lines then
                -- TODO: instead of denying, ask whether annotation should be deleted instead
                -- currently this just prints msg without updating annotation!
                curr_mark = mark_id
                print('Annotation is empty')
            else
                -- TODO: only do DB operations after checking that the annotation has actually changed
                local buf_txt = vim.api.nvim_buf_get_lines(annot_buf, 0, -1, true)
                if is_updt then
                    db.updt_annot(parent_buf_path, cursor_ln, buf_txt)
                    curr_mark = mark_id
                    vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
                        id = curr_mark,
                        sign_text = M.config.annot_sign,
                        sign_hl_group = M.config.annot_sign_hl
                    })
                    print('Modified annotation. is_updt: ', is_updt)
                else
                    db.create_annot(parent_buf_path, cursor_ln, buf_txt)
                    curr_mark = vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
                        sign_text = M.config.annot_sign,
                        sign_hl_group = M.config.annot_sign_hl
                    })
                    -- TODO: seems a bit messy; are we using the funcs properly?
                    local target = curr_extmarks[extmark_parent_buf]
                    local curr_mark_pos = vim.api.nvim_buf_get_extmark_by_id(extmark_parent_buf, ns, curr_mark, {})
                    if target then
                        table.insert(target, {curr_mark, curr_mark_pos[1], curr_mark_pos[2]})
                    else
                        curr_extmarks[extmark_parent_buf] = { {curr_mark, curr_mark_pos[1], curr_mark_pos[2]}}
                    end
                    print('Created new annotation. is_updt: ', is_updt)
                    print('Bufnr ', extmark_parent_buf, ' sent for monitoring')
                    monitor_buf(extmark_parent_buf)
                end
            end
        end,
        group=au_group_edit,
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
        vim.api.nvim_buf_set_extmark(extmark_parent_buf, ns, cursor_ln, 0, {
            id = mark_id,
            sign_text = M.config.annot_sign,
            sign_hl_group = M.config.annot_sign_hl_current
        })

        -- TODO: I *think* this is proper use of vim.schedule? intent: schedule prompt for after window shown
        vim.schedule(function()
            local confirm = vim.fn.input('Are you sure you want to delete this annotation? (y/n): ')
            if confirm:lower() == 'y' then
                -- local mark_id = existing_extmark[1][1]
                vim.api.nvim_buf_del_extmark(extmark_parent_buf, ns, mark_id)
                db.del_annot(parent_buf_path, cursor_ln)
                -- TODO: for updating curr_extmarks; clean this up
                local target = curr_extmarks[extmark_parent_buf]
                for i, extmark in ipairs(target) do
                    if mark_id == extmark[1] then
                        table.remove(target, i)
                        break
                    end
                end
                print('Deleted successfully. Will hide window ' .. annot_win)
                -- TODO: this seems clunky but it works?
                -- vim.cmd('noautocmd')
                -- doesn't work if create_annotation hasn't been called yet
                -- vim.api.nvim_del_augroup_by_name('AnnotateEdit')
                -- vim.api.nvim_win_hide(annot_win)
                vim.cmd('noautocmd lua vim.api.nvim_win_hide(' .. annot_win .. ')')
            else
                print('Annotation NOT deleted')
            end
        end)
    end
end

-- TODO: is there a better way to specify/config hl? or did we set a sensible default at least
-- TODO: use webdevicons for symbol instead?
local default_opts = {
    annot_sign = '󰍕',
    annot_sign_hl = 'Comment',
    annot_sign_hl_current = 'FloatBorder',
    annot_win_width = 25,
    annot_win_padding = 2
}

function M.setup(opts)
    M.config = vim.tbl_deep_extend('force', default_opts, opts or {})
    -- TODO: need to add another event(s) to track when user opens a new buffer that they
    -- might start setting annotations? or already handled enough by the create_annotation func?
    -- considering BufNew, BufAdd, BufReadPre, BufReadPost
    -- TODO: change pattern to be more specific?
    local au_group_set = vim.api.nvim_create_augroup('AnnotateSet', {clear=true})
    vim.api.nvim_create_autocmd({'BufReadPost'}, {
        callback = function()
            set_annotations()
        end,
        group = au_group_set,
        pattern = '*'
    })
end

-- TODO: delete these helper funcs
function M.list_annotations()
    local namespace = vim.api.nvim_create_namespace('annotate')
    local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {})
    P(marks)
end

function M.check_line()
    local extmark_parent_win = vim.api.nvim_get_current_win()
    local extmark_parent_buf = vim.api.nvim_win_get_buf(extmark_parent_win)
    local cursor_ln = vim.api.nvim_win_get_cursor(extmark_parent_win)[1] - 1
    local ns = vim.api.nvim_create_namespace('annotate')
    local existing_extmark = vim.api.nvim_buf_get_extmarks(extmark_parent_buf, ns, {cursor_ln, 0}, {cursor_ln, 0}, {})
    P(existing_extmark)
    print('Cursor @ ', cursor_ln + 1)
end

function M.show_extmarks()
    print('extmarks ', vim.inspect(curr_extmarks))
    print('extmark bufs ', vim.inspect(curr_extmark_bufs))
end

return M
