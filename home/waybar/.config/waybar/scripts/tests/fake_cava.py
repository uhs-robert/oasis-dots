# waybar/.config/waybar/scripts/fake_cava.py
#!/usr/bin/env python3
import time, itertools

bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
for i in itertools.cycle(range(len(bars))):
    s = " ".join(bars[(i + j) % len(bars)] for j in range(10))
    print('{"text":"%s"}' % s, flush=True)
    time.sleep(0.5)
