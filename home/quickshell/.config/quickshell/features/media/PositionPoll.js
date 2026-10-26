.pragma library

// How often MprisPlayer.position is re-read (it never pushes updates), in ms, or 0 for not at all. Nothing viewing it
// means no polling. While playing the view needs a tick a second; while paused the position moves only when a track
// changes or another client seeks, so a slow poll catches the outside seek and our own actions refresh at once.
const PLAYING_MS = 1000;
const PAUSED_MS = 2000;

function interval(viewed, playing) {
    if (!viewed) return 0;
    return playing ? PLAYING_MS : PAUSED_MS;
}
