# Only explicit Host aliases in the local config; patterns are not destinations.
termux_ssh_hosts() {
    [[ -r "$HOME/.ssh/config" ]] || return 0
    awk '
        { sub(/#.*/, ""); sub(/^[ \t]*/, ""); sub(/^[Hh][Oo][Ss][Tt][ \t]*=[ \t]*/, "Host ") }
        tolower($1) == "host" {
            for (i = 2; i <= NF; i++) {
                host = $i
                gsub(/^[\047"]|[\047"]$/, "", host)
                if (host != "" && host !~ /[!*?\[]/ && host !~ /^-/) print host
            }
        }
    ' "$HOME/.ssh/config" | sort -u
}
