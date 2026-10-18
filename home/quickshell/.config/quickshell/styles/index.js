.pragma library
.import "../theme/StyleSchema.js" as Schema
.import "goldeneye/watch_tokens.js" as WatchTokens
.import "terminal/tokens.js" as Terminal
.import "crt/tokens.js" as Crt
.import "nes/tokens.js" as Nes
.import "snes/tokens.js" as Snes
.import "ps1/tokens.js" as Ps1
.import "goldeneye/tokens.js" as Goldeneye
.import "metroid/tokens.js" as Metroid
.import "ps2/tokens.js" as Ps2
.import "tie/tokens.js" as Tie
.import "reticle/tokens.js" as Reticle
.import "halflife/tokens.js" as Halflife
.import "gameboy/tokens.js" as Gameboy
.import "ff7/tokens.js" as Ff7
.import "oasis/tokens.js" as Oasis
.import "modern/tokens.js" as Modern
.import "neovim/tokens.js" as Neovim

// Watched by Style.qml for hot reload, relative to this folder.
var sources = ["../theme/StyleSchema.js", "index.js", "goldeneye/watch_tokens.js", "terminal/tokens.js", "crt/tokens.js", "nes/tokens.js", "snes/tokens.js", "ps1/tokens.js", "goldeneye/tokens.js", "metroid/tokens.js", "ps2/tokens.js", "tie/tokens.js", "reticle/tokens.js", "halflife/tokens.js", "gameboy/tokens.js", "ff7/tokens.js", "oasis/tokens.js", "modern/tokens.js", "neovim/tokens.js"];

// Every style's raw token set by name: the schema defaults with the style's overrides laid over them.
function build(t, version) {
    const pal = WatchTokens.palette(t);
    const ctx = {
        version: version,
        pal: pal,
        classic_tokens: WatchTokens.tokens(pal, WatchTokens.classic_ramp()),
        theme_tokens: WatchTokens.tokens(pal, WatchTokens.theme_ramp(t))
    };
    ctx.defaults = Schema.defaults(t, ctx);
    const style = (s, extra) => Object.assign({}, ctx.defaults, s.overrides(t, ctx), extra);
    return {
        "terminal": style(Terminal),
        "crt": style(Crt),
        "nes": style(Nes),
        "snes": style(Snes),
        "ps1": style(Ps1),
        "goldeneye": style(Goldeneye, ctx.theme_tokens),
        "metroid": style(Metroid),
        "ps2": style(Ps2),
        "tie": style(Tie),
        "reticle": style(Reticle),
        "halflife": style(Halflife),
        "gameboy": style(Gameboy),
        "ff7": style(Ff7),
        "oasis": style(Oasis),
        "modern": style(Modern),
        "neovim": style(Neovim)
    };
}
