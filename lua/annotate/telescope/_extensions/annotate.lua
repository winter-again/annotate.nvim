local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')

local function prep_annots(annots)
    local res = {}
    return res
end

local function annotations(opts)
    opts = opts or {}
    local ns = vim.api.nvim_create_namespace('annotate')
    local annots = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
    local bufname = vim.api.nvim_buf_get_name(0)
    pickers.new(opts, {
        prompt_title = 'Annotations',
        finder = finders.new_table({
            results = annots,
            entry_maker = function(entry)
                local res = 'Line: ' .. entry[2] + 1 .. ' id: ' .. entry[2]
                return {
                    value = entry[2] + 1,
                    display = res,
                    ordinal = entry[2],
                    -- TODO: need path or filename for the qflist_previewer
                    path = bufname,
                    lnum = entry[2] + 1
                }
            end
        }),
        sorter = conf.generic_sorter(opts),
        -- previewer = conf.grep_previewer(opts),
        previewer = conf.qflist_previewer(opts),
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                -- vim.api.nvim_command(tostring(selection.lnum))
                vim.api.nvim_win_set_cursor(0, {selection.lnum, 0})
            end)
            return true
        end
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
