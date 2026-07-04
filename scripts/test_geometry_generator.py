import random

class ProceduralShipTester:
    def __init__(self):
        self.MIN_OVERLAP = 40
        self.ROOM_GAP = 10
        self.DIR_FLIP = {
            "+x": "-x", "-x": "+x",
            "+z": "-z", "-z": "+z"
        }

    def flip_dir(self, d: str) -> str:
        return self.DIR_FLIP.get(d, d)

    def compute_overlap(self, parent: dict, child: dict, direction: str) -> int:
        if direction in ["+x", "-x"]:
            lo = max(int(parent.get("startY", 0)), int(child.get("startY", 0)))
            hi = min(int(parent.get("endY", 0)), int(child.get("endY", 0)))
            return max(0, hi - lo)
        else:
            lo = max(int(parent.get("startX", 0)), int(child.get("startX", 0)))
            hi = min(int(parent.get("endX", 0)), int(child.get("endX", 0)))
            return max(0, hi - lo)

    def has_collision(self, candidate: dict, placed: list) -> bool:
        csx = int(candidate.get("startX", 0))
        cex = int(candidate.get("endX", 0))
        csy = int(candidate.get("startY", 0))
        cey = int(candidate.get("endY", 0))
        for p in placed:
            psx = int(p.get("startX", 0))
            pex = int(p.get("endX", 0))
            psy = int(p.get("startY", 0))
            pey = int(p.get("endY", 0))
            sep_x = (cex + self.ROOM_GAP <= psx) or (pex + self.ROOM_GAP <= csx)
            sep_y = (cey + self.ROOM_GAP <= psy) or (pey + self.ROOM_GAP <= csy)
            if not sep_x and not sep_y:
                return True
        return False

def run_tests():
    tester = ProceduralShipTester()
    print("Running geometry validation tests...")
    
    # Case 1: Direct overlap collision
    bad_parent = {"startX": 0, "endX": 1000, "startY": 0, "endY": 1000}
    bad_child = {"startX": 500, "endX": 1500, "startY": 500, "endY": 1500}
    existing_room = {"startX": 800, "endX": 1200, "startY": 800, "endY": 1200}
    
    collision = tester.has_collision(bad_child, [existing_room])
    print(f"Collision test: {'PASSED' if collision else 'FAILED'} (Expected: True)")
    
    # Case 2: Overlap depth check
    overlap = tester.compute_overlap(bad_parent, bad_child, "+x")
    print(f"Overlap test: {overlap} (Expected > 0)")

    # Case 3: No collision (far away)
    safe_child = {"startX": 2000, "endX": 2500, "startY": 2000, "endY": 2500}
    collision_safe = tester.has_collision(safe_child, [existing_room])
    print(f"Safe collision test: {'PASSED' if not collision_safe else 'FAILED'} (Expected: False)")

if __name__ == '__main__':
    run_tests()
