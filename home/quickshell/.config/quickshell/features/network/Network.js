.pragma library

var wifi_glyphs = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"];

function signal_glyph(strength) {
    if (strength <= 0.2) return wifi_glyphs[0];
    if (strength <= 0.4) return wifi_glyphs[1];
    if (strength <= 0.6) return wifi_glyphs[2];
    if (strength <= 0.8) return wifi_glyphs[3];
    return wifi_glyphs[4];
}

// Dedupe scan results by SSID, keeping the strongest signal, sorted best-first.
function build_network_list(networks) {
    const by_name = {};
    for (const n of networks) {
        if (!by_name[n.name] || n.signalStrength > by_name[n.name].signalStrength) by_name[n.name] = n;
    }
    return Object.values(by_name).sort((a, b) => b.signalStrength - a.signalStrength);
}

function parse_ipv4(text) {
    const m = text.match(/inet (\d+\.\d+\.\d+\.\d+)/);
    return m ? m[1] : "";
}

var details_script = "nmcli -t -e no -m multiline -f IN-USE,SSID,BSSID,BAND,CHAN,FREQ,SIGNAL,SECURITY device wifi list ifname \"$1\" --rescan no; "
    + "echo @@DEV; nmcli -t -e no -f GENERAL.HWADDR,GENERAL.CON-UUID,CAPABILITIES.SPEED,IP4,IP6 device show \"$1\"; "
    + "echo @@SAVED; u=$(nmcli -t -f UUID,TYPE connection show | sed -n 's/:802-11-wireless$//p'); "
    + "[ -z \"$u\" ] || nmcli -t -e no -f connection.uuid,connection.id,connection.timestamp,connection.autoconnect,connection.metered,ipv4.dns,802-11-wireless.ssid connection show $u";

// Errors go to stdout so one collector sees them; reapply runs only for the active profile and keeps the link up.
var modify_script = "u=$1; r=$2; shift 2; "
    + "out=$(nmcli connection modify uuid \"$u\" \"$@\" 2>&1) || { printf '%s' \"${out:-nmcli modify failed}\"; exit 1; }; "
    + "[ \"$r\" = 1 ] || exit 0; "
    + "d=$(nmcli -g GENERAL.DEVICES connection show uuid \"$u\"); "
    + "out=$(nmcli device reapply \"$d\" 2>&1) || { printf '%s' \"${out:-nmcli reapply failed}\"; exit 1; }";

function parse_details(text, ssid) {
    const aps = [];
    const saved = [];
    const dev = { ipv4: [], ipv6: [], dns: [], gateway: "", mac: "", speed: "", con_uuid: "" };
    let section = "aps";
    for (const line of text.split("\n")) {
        if (line === "@@DEV" || line === "@@SAVED") {
            section = line;
            continue;
        }
        const i = line.indexOf(":");
        if (i < 0) continue;
        const key = line.slice(0, i).replace(/\[\d+\]$/, "");
        const value = line.slice(i + 1);
        if (section === "aps") {
            if (key === "IN-USE") aps.push({ in_use: value === "*" });
            else if (aps.length > 0) aps[aps.length - 1][key] = value;
        } else if (section === "@@DEV") {
            if (key === "IP4.ADDRESS") dev.ipv4.push(value);
            else if (key === "IP6.ADDRESS" && !value.startsWith("fe80:")) dev.ipv6.push(value);
            else if (key === "IP4.DNS" || key === "IP6.DNS") dev.dns.push(value);
            else if (key === "IP4.GATEWAY") dev.gateway = value;
            else if (key === "GENERAL.HWADDR") dev.mac = value;
            else if (key === "GENERAL.CON-UUID") dev.con_uuid = value;
            else if (key === "CAPABILITIES.SPEED") dev.speed = value;
        } else if (key === "connection.uuid") {
            saved.push({ uuid: value });
        } else if (saved.length > 0) {
            saved[saved.length - 1][key] = value;
        }
    }

    const matches = aps.filter(a => a.SSID === ssid).sort((a, b) => Number(b.SIGNAL) - Number(a.SIGNAL));
    const ap = matches.find(a => a.in_use) || matches[0] || null;
    const profiles = saved.filter(c => c["802-11-wireless.ssid"] === ssid).sort((a, b) => Number(b["connection.timestamp"]) - Number(a["connection.timestamp"]));
    const p = profiles.find(c => c.uuid === dev.con_uuid) || profiles[0] || null;
    return {
        loaded: true,
        ap: ap,
        dev: dev,
        profile: p ? {
            uuid: p.uuid,
            name: p["connection.id"] || "",
            active: p.uuid === dev.con_uuid,
            autoconnect: p["connection.autoconnect"] === "yes",
            metered: p["connection.metered"] || "unknown",
            dns: (p["ipv4.dns"] || "").split(",").map(d => d.trim()).filter(d => d !== "")
        } : null
    };
}
