"""Fake MARS device: streams ML/AP floats to the game over UDP (port 4242).

    python tools/mars_sim.py            # smooth figure-8 weight shifts
    python tools/mars_sim.py 192.168.1.20

Replace the generator with your real MARS reader (serial/BLE/SDK) and keep the
same send format:  "ml,ap"  (or JSON {"ml":..,"ap":..}).  Units are arbitrary;
use Calibrate in-game to set the centre and Auto-Range to fit the patient's reach.
"""
import math, socket, sys, time

host = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
t0 = time.time()
while True:
    t = time.time() - t0
    ml = 0.12 * math.sin(t * 0.7)            # medio-lateral, +right
    ap = 0.08 * math.sin(t * 0.35 + 1.0)     # anterior-posterior, +forward
    sock.sendto(f"{ml:.4f},{ap:.4f}".encode(), (host, 4242))
    time.sleep(1 / 60)
