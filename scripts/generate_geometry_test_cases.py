import random
import json

# This script is a prototype for a tool to generate test cases for the procedural 
# ship generator in the Stargate Universe project. It generates geometric scenarios
# (parent rooms and child rooms) and evaluates them against collision and overlap 
# logic to ensure no illegal geometry (illegal overlaps or gaps) is created.

class ProceduralShipGeometryTester:
    """
    A Python-based simulation of the GDScript geometry logic in 
    stargate-universe/scripts/procedural_ship.gd.
    Used to generate and validate test cases for the procedural generator.
    """
    def __init__(self, room_gap: int = 10, min_overlap: int = 40):
        self.room_gap = room_gap
        self.min_overlap = min_overlap

    def compute_overlap(self, parent: dict, child: dict, direction: str) -> int:
        """Simulates the _compute_overlap function from GDScript."""
        if direction in ["+x", "-x"]:
            lo = max(int(parent.get("startY", 0)), int(child.get("startY", 0)))
            hi = min(int(parent.get("endY", 0)), int(child.get("endY", 0)))
            return max(0, hi - lo)
        else:
            lo = max(int(parent.get("startX", 0)), int(child.get("startX", 0)))
            hi = min(int(parent.get("endX", 0)), int(child.get("endX", 0)))
            return max(0, hi - lo)

    def check_collision(self, candidate: dict, placed: list) -> bool:
        """Simulates the _has_collision function from GDScript."""
        csx = int(candidate.get("startX", 0))
        cex = int(candidate.get("endX", 0))
        csy = int(candidate.get("startY", 0))
        cey = int(candidate.get("endY", 0))
        for p in placed:
            psx = int(p.get("startX", 0))
            pex = int(p.get("endX", 0))
            psy = int(p.get("startY", 0))
            pey = int(p.get("endY", 0))
            # A collision occurs if they are NOT separated by at least the gap on both axes.
            sep_x = (cex + self.room_gap <= psx) or (pex + self.room_gap <= csx)
            sep_y = (cey + self.room_gap <= psy) or (pey + self.room_gap <= csy)
            if not sep_x and not sep_y:
                return True
        return False

    def generate_scenario(self, num_scenarios: int):
        """Generates a set of random geometric scenarios for testing."""
        scenarios = []
        for i in range(num_scenarios):
            # 1. Create a random parent room
            p_w = random.randint(200, 1000)
            p_h = random.randint(200, 1000)
            parent = {"startX": 0, "endX": p_w, "startY": 0, "endY": p_h}

            # 2. Create a potential child room
            # We randomize its position to create both valid and invalid cases
            c_w = random.randint(100, 400)
            c_h = random.randint(100, 400)
            
            # The child is placed relative to the parent's walls to test edge cases.
            # We'll try 4 directions: +x, -x, +z, -z
            direction = random.choice(["+x", "-x", "+z", "-z"])
            
            # Calculate a position that is 'mostly' valid/invalid
            # If +x, it should be near endX
            if direction == "+x":
                start_x = p_w
                start_y = random.randint(0, max(0, p_h - c_h))
            elif direction == "-x":
                start_x = -c_w
                start_y = random.randint(0, max(0, p_h - c_h))
            elif direction == "+z":
                start_x = random.randint(0, max(0, p_w - c_w))
                start_y = p_h
            else: # -z
                start_x = random.randint(0, max(0, p_w - c_w))
                start_y = -c_h

            child = {"startX": start_x, "endX": start_x + c_w, "startY": start_y, "endY": start_y + c_h}
            
            # Calculate expected values
            overlap = self.compute_overlap(parent, child, direction)
            
            scenarios.append({
                "id": i,
                "direction": direction,
                "parent": parent,
                "child": child,
                "expected_overlap_min": self.min_overlap,
                "actual_overlap": overlap,
                "is_valid_placement": overlap >= self.min_overlap
            })
        return scenarios

def main():
    tester = ProceduralShipGeometryTester()
    print("--- Procedural Ship Exploration Geometry Test Generator ---")
    
    # Generate 100 scenarios
    scenarios = tester.generate_scenario(100)
    
    # Analyze results
    valid_count = sum(1 for s in scenarios if s["is_valid_placement"])
    invalid_count = 100 - valid_count
    
    print(f"Generated {len(scenarios)} random scenarios.")
    print(f"Valid placements (meeting min_overlap): {valid_count}")
    print(f"Invalid/Partial placements (below min_overlap): {invalid_count}")
    
    # Save as JSON for use in actual automated test suites
    output_path = "geometry_test_scenarios.json"
    with open(output_path, "w") as f:
        json.dump(scenarios, f, indent=2)
    print(f"Successfully saved scenarios to {output_path}")

if __name__ == "__main__":
    main()
