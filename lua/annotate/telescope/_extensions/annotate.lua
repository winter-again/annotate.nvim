local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values

local function prep_annots(annots)
    local res = {}
    return res
end

local function annotations(opts)
    opts = opts or {}
    local ns = vim.api.nvim_create_namespace('annotate')
    local annots = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
    pickers.new(opts, {
        prompt_title = 'Annotations',
        finder = finders.new_table({
            results = annots,
            entry_maker = function(entry)
                local res = 'Line: ' .. entry[2] + 1 .. ' id: ' .. entry[2]
                return {
                    value = entry,
                    display = res,
                    ordinal = entry[2],
                    lnum = entry[2]
                }
            end
        }),
        sorter = conf.generic_sorter(opts)
    }):find()
end

annotations(require('telescope.themes').get_dropdown())


-- return require('telescope').register_extension({
--     setup = function(ext_config, config)
--     end,
--     exports = {
--         stuff = require('annotate').stuff
--     }
-- })
