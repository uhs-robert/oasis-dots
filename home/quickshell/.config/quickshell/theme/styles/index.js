.pragma library
.import "../StyleSchema.js" as Schema
.import "watch.js" as WatchTokens
.import "terminal.js" as Terminal
.import "crt.js" as Crt
.import "nes.js" as Nes
.import "snes.js" as Snes
.import "ps1.js" as Ps1
.import "goldeneye.js" as Goldeneye
.import "metroid.js" as Metroid
.import "ps2.js" as Ps2
.import "tie.js" as Tie
.import "reticle.js" as Reticle
.import "halflife.js" as Halflife
.import "gameboy.js" as Gameboy
.import "ff7.js" as Ff7
.import "oasis.js" as Oasis
.import "modern.js" as Modern
.import "neovim.js" as Neovim

// Watched by Style.qml for hot reload, relative to this folder.
var sources = ["../StyleSchema.js", "index.js", "watch.js", "terminal.js", "crt.js", "nes.js", "snes.js", "ps1.js", "goldeneye.js", "metroid.js", "ps2.js", "tie.js", "reticle.js", "halflife.js", "gameboy.js", "ff7.js", "oasis.js", "modern.js", "neovim.js"];

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
