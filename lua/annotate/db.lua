local tbl = require('sqlite.tbl')
local M = {}

M.annots_tbl = tbl('annots_tbl', {
    id = true, -- same as {type='integer', required=true, primary=true}
    buf_full_path = { 'text', required = true },
    extmark_ln = { 'number', required = true },
    text = { 'text', required = true },
})

-- function M.show_db()
--     P(annots_tbl:get())
-- end

function M.get_annot(parent_buf_path, extmark_ln)
    local annot_txt = M.annots_tbl:get({
        select = {
            'text',
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln,
        },
    })
    return annot_txt
end

function M.get_all_annot(parent_buf_path)
    local annots = M.annots_tbl:get({
        select = {
            'buf_full_path',
            'extmark_ln',
        },
        where = {
            buf_full_path = parent_buf_path,
        },
    })
    return annots
end

function M.create_annot(parent_buf_path, extmark_ln, annot)
    local annot_concat = table.concat(annot, '\\n')
    M.annots_tbl:insert({
        buf_full_path = parent_buf_path,
        extmark_ln = extmark_ln,
        text = annot_concat,
    })
end

function M.updt_annot(parent_buf_path, extmark_ln, annot)
    local annot_concat = table.concat(annot, '\\n')
    M.annots_tbl:update({
        set = {
            text = annot_concat,
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln,
        },
    })
end

function M.updt_annot_pos(parent_buf_path, old_extmark_ln, new_extmark_ln)
    M.annots_tbl:update({
        set = {
            extmark_ln = new_extmark_ln,
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = old_extmark_ln,
        },
    })
end

function M.migrate_annot_char_sep()
    -- { {'buf_full_path' = ..., 'text' = ..., ... } }
    local annots = M.annots_tbl:get({
        select = {
            'buf_full_path',
            'extmark_ln',
            'id',
            'text',
        },
    })
    local target_str = '``'
    local replacement_str = '\\n'
    for _, item in ipairs(annots) do
        item.text = item.text:gsub(target_str, replacement_str)
    end
    for _, item in ipairs(annots) do
        M.annots_tbl:update({
            set = {
                text = item.text,
            },
            where = {
                buf_full_path = item.buf_full_path,
                extmark_ln = item.extmark_ln,
                id = item.id,
            },
        })
    end
end

function M.del_annot(parent_buf_path, extmark_ln)
    M.annots_tbl:remove({
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln,
        },
    })
end

return M
