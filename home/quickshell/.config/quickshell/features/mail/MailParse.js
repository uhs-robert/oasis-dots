.pragma library

// Reads `desertfox --app thunderbird mail folders --json`. Everything inside the envelope came from outside (feed
// titles and shared IMAP folders let third parties name folders), so it is checked here and drawn as plain text only.

var MAX_TEXT = 80;
var MAX_PREVIEW_FROM = 40;
var MAX_PREVIEW_SUBJECT = 60;
// A folder id goes on a command line as one argument. Inner spaces are real ("[Gmail]/Sent Mail"); it must not start with a
// dash (an option), start or end with whitespace, or hold a control character.
var SAFE_ID = /^[^\s\-](?:[^\u0000-\u001f\u007f-\u009f\u2028\u2029]{0,1022}[^\s\u0000-\u001f\u007f-\u009f])?$/;

// A folder segment that marks a trash or a junk folder, whatever the account's server calls it.
var TRASH_NAMES = ["trash", "bin", "deleted items", "deleted messages"];
var JUNK_NAMES = ["junk", "spam", "junk email", "junk e-mail", "bulk mail"];

function clean_text(value, max) {
    var limit = max || MAX_TEXT;
    var text = String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g, " ").trim();
    return text.length > limit ? text.slice(0, limit - 1) + "\u2026" : text;
}

// The text between the first and last line, only when the last line carries the first line's nonce. Null otherwise.
function strip_envelope(out, what) {
    var lines = String(out).split("\n");
    while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
    if (lines.length < 2) return null;
    var head = new RegExp("^<<<UNTRUSTED mail " + what + " nonce=([0-9a-f]+)>>>$").exec(lines[0]);
    if (!head || lines[lines.length - 1] !== "<<<END " + head[1] + ">>>") return null;
    return lines.slice(1, -1).join("\n");
}

// { ok: true, folders: [{ id, name, path, account, unread, total }], truncated } or { ok: false }.
function parse_folders(out) {
    var body = strip_envelope(out, "folders");
    if (body === null) return { ok: false };
    var data;
    try {
        data = JSON.parse(body);
    } catch (e) {
        return { ok: false };
    }
    if (!data || !Array.isArray(data.folders)) return { ok: false };
    var folders = [];
    data.folders.forEach(function (row) {
        if (!row || !Number.isInteger(row.unread) || row.unread < 0) return;
        folders.push({
            // The raw id, not the display text: a cut id would name another folder. Empty when it is unsafe to pass on.
            id: typeof row.id === "string" && SAFE_ID.test(row.id) ? row.id : "",
            name: clean_text(row.name),
            path: clean_text(row.path),
            // From the full path: `path` is cut for display and may have lost the segment that names the kind.
            kind: kind_of(row.path),
            account: clean_text(row.account),
            unread: row.unread,
            total: Number.isInteger(row.total) && row.total >= 0 ? row.total : 0
        });
    });
    return { ok: true, folders: folders, truncated: data.truncated === true };
}

// What a run means: "ok" (with the parse), "unavailable" (no CLI, an old CLI, Thunderbird or the bridge not running:
// nothing the user needs a pill for) or "refused" (the bridge answered but will not share, with its message).
function classify(code, out, err) {
    if (code === 0) {
        var parsed = parse_folders(out);
        return parsed.ok ? { state: "ok", folders: parsed.folders, truncated: parsed.truncated, message: "" } : { state: "refused", folders: [], truncated: false, message: "Unreadable reply" };
    }
    if (code === 1) return { state: "refused", folders: [], truncated: false, message: refusal_message(err) };
    return { state: "unavailable", folders: [], truncated: false, message: "" };
}

function refusal_message(err) {
    var line = String(err).split("\n").filter(function (l) { return l.trim() !== ""; })[0] || "";
    return clean_text(line.replace(/^desertfox:\s*/, "")) || "Refused";
}

function segments(path) {
    return String(path).toLowerCase().split("/").map(function (s) { return s.trim(); }).filter(function (s) { return s !== ""; });
}

// Gmail over IMAP shows every message again under these, with the same read flags as the inbox.
var GMAIL_PARENTS = ["[gmail]", "[google mail]"];
var GMAIL_VIEWS = ["all mail", "important", "starred"];

function is_gmail_view(parts) {
    return parts.length === 2 && GMAIL_PARENTS.indexOf(parts[0]) >= 0 && GMAIL_VIEWS.indexOf(parts[1]) >= 0;
}

function kind_of(path) {
    var parts = segments(path);
    if (is_gmail_view(parts)) return "view";
    if (parts.some(function (s) { return TRASH_NAMES.indexOf(s) >= 0; })) return "trash";
    if (parts.some(function (s) { return JUNK_NAMES.indexOf(s) >= 0; })) return "junk";
    return "";
}

// The folders that count: those with unread mail, minus the Gmail views (always) and the kinds the settings skip (`skip` is { trash, junk }).
function counted(folders, skip) {
    return folders.filter(function (f) {
        if (f.unread <= 0) return false;
        return f.kind !== "view" && !(f.kind !== "" && skip[f.kind]);
    });
}

function total_unread(folders) {
    return folders.reduce(function (sum, f) { return sum + f.unread; }, 0);
}

// { ok: true, messages: [{ from, subject, date }] } from `mail list <folder> --unread --json`, or { ok: false }. Only
// these three fields are kept, each cut short for the popup; ids and flags are not read.
function parse_messages(out) {
    var body = strip_envelope(out, "list");
    if (body === null) return { ok: false };
    var data;
    try {
        data = JSON.parse(body);
    } catch (e) {
        return { ok: false };
    }
    if (!data || !Array.isArray(data.messages)) return { ok: false };
    var messages = [];
    data.messages.forEach(function (row) {
        if (!row || typeof row !== "object") return;
        messages.push({
            from: clean_text(row.from, MAX_PREVIEW_FROM),
            subject: clean_text(row.subject, MAX_PREVIEW_SUBJECT),
            date: typeof row.date === "string" && !isNaN(Date.parse(row.date)) ? row.date : ""
        });
    });
    return { ok: true, messages: messages };
}

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// The time of day for a message from today, else "Nov 17"; empty for a bad date.
function short_date(iso, now) {
    var when = new Date(iso);
    if (isNaN(when.getTime())) return "";
    if (when.toDateString() === now.toDateString()) return ("0" + when.getHours()).slice(-2) + ":" + ("0" + when.getMinutes()).slice(-2);
    return MONTHS[when.getMonth()] + " " + when.getDate();
}

// Headers are fetched and drawn only when the setting is on and nobody else can see the screen.
function preview_allowed(setting_on, recording, shared, locked) {
    return setting_on === true && !recording && !shared && !locked;
}
