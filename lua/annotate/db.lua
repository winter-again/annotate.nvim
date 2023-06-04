local sqlite = require('sqlite.db')
local tbl = require('sqlite.tbl')
-- TODO: should we put this in a folder?
local uri = vim.fn.stdpath('data') .. '/annotations_db' -- '/home/andrew/.local/shrae/nvim/annotations_db'
local M = {}

-- annotations table
local annots_tbl = tbl('annots_tbl', {
    id = true, -- same as {type='integer', required=true, primary=true}
    buf_full_path = {'text', required=true},
    extmark_row = {'number', required=true, unique=true},
    text = {'text', required=true}
})

-- DB object setup?
local db = sqlite({
    uri = uri,
    annots_tbl = annots_tbl,
    opts = {}
})

function M.show_db()
    P(annots_tbl:get())
end

function M.get_annot(buf_path, extmark_ln)
    local annot_txt = annots_tbl:get({
        select = {
            'text'
        },
        where = {
            buf_full_path = buf_path,
            extmark_row = extmark_ln
        }
    })
    return annot_txt
end

function M.get_all_annot(buf_path)
    local annots = annots_tbl:get({
        select = {
            'buf_full_path',
            'extmark_row'
        },
        where = {
            buf_full_path = buf_path
        }
    })
    return annots
end

-- handle the parsing/formatting of the text
-- and save to database
function M.create_annot(buf_path, extmark_ln, annot)
    -- print('You gave me a line of ' .. extmark_ln .. ' and this text ' .. annot[1])
    local annot_concat = table.concat(annot, '``') -- '``' hopefully this pattern is uncommon in annots
    annots_tbl:insert({
        buf_full_path = buf_path,
        extmark_row = extmark_ln,
        text = annot_concat
    })
    print('Created DB entry')
end

function M.updt()

end

function M.del_annot(buf_path, extmark_ln)
    annots_tbl:remove({
        where = {
            buf_full_path = buf_path,
            extmark_row = extmark_ln
        }
    })
end

return M
