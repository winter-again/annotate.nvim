# annotate.nvim

> [!NOTE]
> This repo will be archived on 2024-02-23. There remain some bugs and I may make some additional changes before the aforementioned date, but I don't have the motivation to continue working on this plugin.

A plugin for creating and storing notes (annotations) related to a line of code/text. It uses Neovim's extended marks and a [SQLite database](https://github.com/kkharji/sqlite.lua) to store annotation information.

https://github.com/winter-again/annotate.nvim/assets/63322884/248a3410-bc51-46b4-a298-f19ba4c4c449

## Installation & configuration

With [folke/lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'winter-again/annotate.nvim',
  dependencies = {'kkharji/sqlite.lua'},
  config = function()
    require('annotate').setup({
      -- path for the sqlite db file
      db_uri = vim.fn.stdpath('data') .. '/annotations_db',
      -- sign column symbol to use
      annot_sign = '󰍕',
      -- highlight group for symbol
      annot_sign_hl = 'Comment',
      -- highlight group for currently active annotation
      annot_sign_hl_current = 'FloatBorder',
      -- width of floating annotation window
      annot_win_width = 25,
      -- padding to the right of the floating annotation window
      annot_win_padding = 2
    })
  end
 }
```

## Migrating note line separator character

Previously, I'd been using "\`\`" as a separator when concatenating and reconstructing notes that span multiple lines. However, I've changed this to use "\\n" instead. To update all existing notes to use the new character separator, use `require('annotate').migrate_annotation_char_sep()`. 

## Functions

Map these to some keybinding:

`require('annotate').create_annotation()`: Create an annotation at the current cursor line and open floating window for the text. If an annotation already exists there, will open the floating window to allow modification.

`require('annotate').delete_annotation()`: Delete the annotation at the current cursor line, after showing the annotation text and prompting for confirmation.
