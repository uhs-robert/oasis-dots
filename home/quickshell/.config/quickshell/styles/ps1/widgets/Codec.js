.pragma library

// Signal strength (0-1) as a codec frequency: 85% tunes 140.85, full signal 141.00.
function freq(strength) {
    return (140 + Math.max(0, Math.min(1, strength || 0))).toFixed(2);
}
