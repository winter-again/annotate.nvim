# annotate.nvim

**Please note that this plugin is still WIP & unstable. Feel free to open an issue with any bugs or implementation suggestions.**

A plugin for creating and storing notes (annotations) related to a line of code/text. It uses Neovim's extended marks and a [SQLite database](https://github.com/kkharji/sqlite.lua) to store annotation information.

https://github.com/winter-again/annotate.nvim/assets/63322884/248a3410-bc51-46b4-a298-f19ba4c4c449

## Installation & configuration

With [folke/lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'winter-again/annotate.nvim',
  config = function()
    require('annotate').setup({
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

## Functions

Map these to some keybinding:

`require('annotate').create_annotation()`: Create an annotation at the current cursor line and open floating window for the text. If an annotation already exists there, will open the floating window to allow modification.

`require('annotate').delete_annotation()`: Delete the annotation at the current cursor line, after showing the annotation text and prompting for confirmation.
