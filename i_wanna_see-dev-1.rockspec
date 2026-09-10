rockspec_format = "3.0"
package = "i_wanna_see"
version = "dev-1"
source = { url = "git+https://github.com/drewboardman/wanna_see_2.git" }
description = {
    summary = "Removes sources of VFX that block vision in Darktide",
    license = "MIT",
}
dependencies = { "lua >= 5.1, < 5.2" }
test_dependencies = { "busted == 2.3.0-1" }
test = { type = "busted" }
build = { type = "builtin", modules = {} }
