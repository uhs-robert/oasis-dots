// home/quickshell/.config/quickshell/services/NotificationMarkup.js
.pragma library

// Turns a notification body into StyledText that can only show text. Any app, and anyone who can put text into one
// (chat, mail, invites), writes these bodies, so nothing is passed through: the input is read as the freedesktop
// body-markup subset (b, i, u, a href, br, img alt) and the output is rebuilt from escaped pieces.
// StyledText fetches the src of an img and lets headings and lists reshape the card, so those are never emitted.

var max_depth = 8;
var keep_tags = { b: true, i: true, u: true };
var named_entities = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", nbsp: " " };
var safe_href = /^(https?:|mailto:)/i;
var tag_pattern = /^<(\/?)([a-zA-Z][a-zA-Z0-9]*)((?:[^>"']|"[^"]*"|'[^']*')*)>/;
var attribute_pattern = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;

function escape(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

// Reads &amp; and numeric entities back to characters; an unknown entity stays as typed. Control characters go.
function decode(text) {
    return text.replace(/&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|([a-zA-Z]+));/g, function (whole, dec, hex, name) {
        if (name) return named_entities.hasOwnProperty(name) ? named_entities[name] : whole;
        const code = dec ? parseInt(dec, 10) : parseInt(hex, 16);
        return code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff) ? "" : String.fromCodePoint(code);
    }).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "");
}

function attributes(source) {
    const found = {};
    attribute_pattern.lastIndex = 0;
    for (let m = attribute_pattern.exec(source); m; m = attribute_pattern.exec(source)) {
        const value = m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : "";
        const name = m[1].toLowerCase();
        if (!found.hasOwnProperty(name)) found[name] = decode(value);
    }
    return found;
}

// The href with whitespace removed (browsers ignore it inside a scheme, "java\nscript:"), or "" when not allowed.
function clean_href(raw) {
    const href = (raw || "").replace(/[\s\u0000-\u001f\u007f-\u009f]/g, "");
    return safe_href.test(href) ? href : "";
}

function sanitize(body) {
    const source = String(body === undefined || body === null ? "" : body).replace(/\r\n?/g, "\n");
    // Each entry is the tag name, with "a" kept for a link whose href was refused so its closing tag still pairs.
    const open = [];
    let out = "";
    let i = 0;

    function emit_open(name, shown) {
        if (open.length >= max_depth) return;
        open.push({ name: name, html: shown });
        out += shown;
    }

    function emit_close(name) {
        let at = -1;
        for (let k = open.length - 1; k >= 0; k--) {
            if (open[k].name === name) { at = k; break; }
        }
        if (at < 0) return;
        const reopen = open.slice(at + 1);
        for (let k = open.length - 1; k >= at; k--) {
            if (open[k].html !== "") out += "</" + open[k].name + ">";
        }
        open.length = at;
        reopen.forEach(function (tag) { open.push(tag); out += tag.html; });
    }

    while (i < source.length) {
        const ch = source.charAt(i);
        if (ch === "<") {
            const m = tag_pattern.exec(source.slice(i));
            if (m) {
                const closing = m[1] === "/";
                const name = m[2].toLowerCase();
                i += m[0].length;
                // <b/> or <a href=".."/> opens no scope, so it must not format the text after it.
                if (/\/\s*$/.test(m[3]) && name !== "br" && name !== "img") continue;
                if (keep_tags[name]) {
                    if (closing) emit_close(name);
                    else emit_open(name, "<" + name + ">");
                } else if (name === "a") {
                    if (closing) emit_close("a");
                    else {
                        const href = clean_href(attributes(m[3]).href);
                        emit_open("a", href === "" ? "" : "<a href=\"" + escape(href) + "\">");
                    }
                } else if (name === "br") {
                    out += "<br>";
                } else if (name === "img" && !closing) {
                    out += escape(attributes(m[3]).alt || "");
                }
                continue;
            }
            out += "&lt;";
            i += 1;
        } else if (ch === "&") {
            const m = /^&(?:#\d{1,7}|#[xX][0-9a-fA-F]{1,6}|[a-zA-Z]+);/.exec(source.slice(i, i + 12));
            if (m) {
                out += escape(decode(m[0]));
                i += m[0].length;
            } else {
                out += "&amp;";
                i += 1;
            }
        } else if (ch === "\n") {
            out += "<br>";
            i += 1;
        } else if (ch === ">") {
            out += "&gt;";
            i += 1;
        } else {
            out += ch === "\"" ? "&quot;" : escape(decode(ch));
            i += 1;
        }
    }

    for (let k = open.length - 1; k >= 0; k--) {
        if (open[k].html !== "") out += "</" + open[k].name + ">";
    }
    return out;
}
