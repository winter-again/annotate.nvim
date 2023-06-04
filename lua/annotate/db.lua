local sqlite = require('sqlite.db')
local tbl = require('sqlite.tbl')
local uri = vim.fn.stdpath('data') .. '/annotations_db' -- '/home/andrew/.local/shrae/nvim/annotations_db'
local M = {}

-- annotations table
local annotations = tbl('annotations', {
    id = true, -- same as {type='integer', required=true, primary=true}
    buf_full_path = {'text', required=true},
    extmark_row = {'number', required=true, unique=true},
    text = {'text', required=true}
})

-- DB object setup?
local db = sqlite({
    uri = uri,
    annotations = annotations,
    opts = {}
})

function M.get()

end

function M.get_all_buf()

end

function M.create_annot(line_num, annot)
    print('OK updating DB..')
end

function M.updt()

end

function M.del()

end

return M
