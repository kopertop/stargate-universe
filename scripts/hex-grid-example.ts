/* eslint-disable @typescript-eslint/no-explicit-any */
import { Hex, HexGrid } from './hex-grid';
import { HexGridRenderer } from './hex-grid-renderer';
import * as THREE from 'three';

/**
 * Example: Test hex grid rendering and axial coordinates
 */
export function testHexGrid() {
  console.log('=== Hex Grid System Test ===\n');

  // Test 1: Create hex grid
  const hexes = HexGrid.generateGrid(5);
  console.log(`Created ${hexes.length} hexes in 5x5 grid`);

  // Test 2: Hex coordinate operations
  const center = new Hex(0, 0);
  const neighbor1 = center.neighbor(1); // East
  const neighbor2 = center.neighbor(6); // Southwest
  console.log('Center:', center);
  console.log('Neighbor (E):', neighbor1);
  console.log('Neighbor (SW):', neighbor2);
  console.log('Distance to neighbor:', Hex.distance(center, neighbor1));

  // Test 3: Range calculation
  const hexesInRange = HexGrid.range(center, 2);
  console.log(`Hexes in range 2 from center: ${hexesInRange.length}`);

  // Test 4: World coordinate conversions
  const hex = new Hex(1, 2);
  const worldPos = HexGrid.toWorld(hex, 1.0, 0.2);
  console.log('Hex (1, 2) world coordinates:', worldPos);
  const backToHex = HexGrid.fromWorld(worldPos.x, worldPos.z, 1.0, 0.2);
  console.log('World to hex:', backToHex);

  // Test 5: Valid neighbors check (for module placement)
  const occupied = new Set(['0,0', '0,1', '1,2']);
  const validNeighbors = HexGrid.validNeighbors(neighbor2, 1, occupied);
  console.log('Valid neighbors for placement (avoiding occupied):', validNeighbors.length);

  console.log('\n=== Hex Grid System Test Complete ===');
}

/**
 * Example: Setup Three.js scene with hex grid
 */
export function setupHexGridScene(container?: HTMLElement) {
  // Create scene
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0a0a1a);

  // Create camera
  const camera = new THREE.PerspectiveCamera(
    60,
    window.innerWidth / window.innerHeight || 16/9,
    0.1,
    1000
  );
  camera.position.set(0, 6, 10);
  camera.lookAt(0, 0, 0);

  // Create renderer
  const renderer = new THREE.WebGLRenderer({ antialias: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  if (container) {
    container.appendChild(renderer.domElement);
  } else {
    document.body.appendChild(renderer.domElement);
  }

  // Add lights
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
  scene.add(ambientLight);

  const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
  directionalLight.position.set(5, 10, 5);
  scene.add(directionalLight);

  // Create hex grid renderer
  const hexGrid = new HexGridRenderer(scene, {
    gridSize: 5,
    hexSize: 1,
    spacing: 0.2,
    highlightColor: 0x4361ee
  });

  // Add center hex
  const centerHex = hexGrid.addHex(0, 0);
  console.log('Added center hex:', centerHex);

  // Add some random hexes
  for (let i = 0; i < 10; i++) {
    const q = Math.floor(Math.random() * 5) - 2;
    const r = Math.floor(Math.random() * 5) - 2;
    hexGrid.addHex(q, r);
  }

  // Highlight center and show hexes
  hexGrid.highlightHex(0, 0);
  console.log('Total hexes:', hexGrid.getHexes().length);

  // Animation loop
  let frame = 0;
  function animate() {
    requestAnimationFrame(animate);

    // Rotate camera slowly
    const time = frame * 0.001;
    camera.position.x = Math.sin(time) * 10;
    camera.position.z = Math.cos(time) * 10;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
    frame++;
  }

  animate();

  // Handle window resize
  window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
  });

  // Cleanup handler
  return {
    scene,
    camera,
    renderer,
    hexGrid,
    cleanup: () => {
      window.removeEventListener('resize', () => {});
      renderer.dispose();
    }
  };
}