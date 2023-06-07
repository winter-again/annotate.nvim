local sqlite = require('sqlite.db')
local tbl = require('sqlite.tbl')
-- TODO: should we put this in a folder?
local uri = vim.fn.stdpath('data') .. '/annotations_db'
local M = {}

local annots_tbl = tbl('annots_tbl', {
    id = true, -- same as {type='integer', required=true, primary=true}
    buf_full_path = {'text', required=true},
    extmark_ln = {'number', required=true},
    text = {'text', required=true}
})

local db = sqlite({
    uri = uri,
    annots_tbl = annots_tbl,
    opts = {}
})

function M.show_db()
    P(annots_tbl:get())
end

function M.get_annot(parent_buf_path, extmark_ln)
    local annot_txt = annots_tbl:get({
        select = {
            'text'
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln
        }
    })
    return annot_txt
end

function M.get_all_annot(parent_buf_path)
    local annots = annots_tbl:get({
        select = {
            'buf_full_path',
            'extmark_ln'
        },
        where = {
            buf_full_path = parent_buf_path
        }
    })
    return annots
end

function M.create_annot(parent_buf_path, extmark_ln, annot)
    local annot_concat = table.concat(annot, '``')
    annots_tbl:insert({
        buf_full_path = parent_buf_path,
        extmark_ln = extmark_ln,
        text = annot_concat
    })
end

function M.updt_annot(parent_buf_path, extmark_ln, annot)
    local annot_concat = table.concat(annot, '``')
    annots_tbl:update({
        set = {
            text = annot_concat
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln
        }
    })
end

function M.updt_annot_pos(parent_buf_path, old_extmark_ln, new_extmark_ln)
    annots_tbl:update({
        set = {
            extmark_ln = new_extmark_ln
        },
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = old_extmark_ln
        }
    })
end

function M.del_annot(parent_buf_path, extmark_ln)
    annots_tbl:remove({
        where = {
            buf_full_path = parent_buf_path,
            extmark_ln = extmark_ln
        }
    })
end

return M
