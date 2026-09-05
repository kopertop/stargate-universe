// Wormhole ride: camera flies down an energy tube. Self-contained scene; tick(t, k) with k = 0..1 progress.
import * as THREE from 'three';

export const createWormhole = () => {
	const scene = new THREE.Scene(); scene.background = new THREE.Color(0x020610);
	const LEN = 320, R = 5;
	const mat = new THREE.ShaderMaterial({
		side: THREE.BackSide,
		uniforms: { uTime: { value: 0 }, uK: { value: 0 } },
		vertexShader: `varying vec2 vUv; varying float vDist; void main(){ vUv = uv; vec4 mv = modelViewMatrix * vec4(position,1.0); vDist = -mv.z; gl_Position = projectionMatrix * mv; }`,
		fragmentShader: `
			precision highp float; varying vec2 vUv; varying float vDist; uniform float uTime, uK;
			float hash21(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p,p+45.32); return fract(p.x*p.y); }
			float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
				return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x), u.y); }
			float fbm(vec2 p){ float s=0.0,a=0.5; for(int i=0;i<4;i++){ s+=a*vnoise(p); p*=2.1; a*=0.5; } return s; }
			void main(){
				float ang = vUv.x * 6.2831853; float len = vUv.y * 60.0;
				// seamless around the tube: sample noise on a circle (cos, sin) instead of the raw angle
				vec2 c = vec2(cos(ang + len * 0.12 + uTime * 0.5), sin(ang + len * 0.12 + uTime * 0.5));
				float n = fbm(c * 1.8 + vec2(0.0, len * 2.0 - uTime * 18.0));
				float streak = pow(fbm(c * 4.0 + vec2(len * 6.0 - uTime * 40.0, 0.0)), 3.0) * 3.0;
				float rings = pow(0.5 + 0.5 * sin(len * 4.0 - uTime * 28.0), 12.0);
				vec3 col = mix(vec3(0.02, 0.15, 0.45), vec3(0.3, 0.75, 1.0), n * 1.6);
				col += vec3(0.8, 0.95, 1.0) * (streak + rings * 0.6);
				float fade = exp(-vDist * 0.035);   // far end dissolves to dark
				float flash = smoothstep(0.85, 1.0, uK) + smoothstep(0.12, 0.0, uK); // white in/out
				gl_FragColor = vec4(mix(col * fade, vec3(0.9, 0.97, 1.0), flash), 1.0);
			}`,
	});
	const tube = new THREE.Mesh(new THREE.CylinderGeometry(R, R, LEN, 48, 1, true), mat);
	tube.rotation.x = Math.PI / 2; tube.position.z = -LEN / 2 + 10; scene.add(tube);
	const camPath = (k, out) => {
		const z = -k * (LEN - 30);
		out.set(Math.sin(k * 9.0) * 1.2, Math.cos(k * 7.0) * 1.0, z);
		return out;
	};
	return {
		scene, tube,
		duration: 3.6,
		tick: (t, k, camera) => {
			mat.uniforms.uTime.value = t; mat.uniforms.uK.value = k;
			camPath(k, camera.position);
			const ahead = camPath(Math.min(1, k + 0.02), new THREE.Vector3());
			camera.up.set(Math.sin(k * 5.0) * 0.35, 1, 0).normalize();
			camera.lookAt(ahead);
		},
	};
};
