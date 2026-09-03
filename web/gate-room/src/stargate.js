// Procedural Stargate — img2threejs-style code-only factory (primitives + shader, no mesh files).
// Proportions mirror objects/stargate.gd: outer r=3.0, inner r=2.4, 9 chevrons at 40°.
// Event horizon = port of shaders/event_horizon.gdshader (fBm + domain warp + polar swirl).
import * as THREE from 'three';

export const GATE = { rOuter: 3.0, rInner: 2.4, chevrons: 9 };

const horizonShader = {
	uniforms: {
		uTime: { value: 0 },
		uRipple: { value: 0 },           // 0..1 impact ripple strength
		uRippleT: { value: 0 },          // seconds since impact
		uRipplePos: { value: new THREE.Vector2() },
		coreColor: { value: new THREE.Color(0.85, 0.97, 1.0) },
		midColor: { value: new THREE.Color(0.12, 0.45, 0.92) },
		edgeColor: { value: new THREE.Color(0.02, 0.12, 0.38) },
	},
	vertexShader: /* glsl */`
		varying vec2 vUv;
		void main(){ vUv = uv * 2.0 - 1.0; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
	fragmentShader: /* glsl */`
		precision highp float;
		varying vec2 vUv;
		uniform float uTime, uRipple, uRippleT; uniform vec2 uRipplePos;
		uniform vec3 coreColor, midColor, edgeColor;
		float hash21(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p,p+45.32); return fract(p.x*p.y); }
		float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
			float a=hash21(i), b=hash21(i+vec2(1,0)), c=hash21(i+vec2(0,1)), d=hash21(i+vec2(1,1));
			return mix(mix(a,b,u.x), mix(c,d,u.x), u.y); }
		float fbm(vec2 p){ float s=0.0, a=0.5; mat2 r=mat2(0.8,0.6,-0.6,0.8);
			for(int i=0;i<5;i++){ s+=a*vnoise(p); p=r*p*2.0; a*=0.5; } return s; }
		void main(){
			vec2 uv = vUv;
			float r = clamp(length(uv),0.0,1.0);
			float ang = atan(uv.y, uv.x);
			float t = uTime;
			// impact ripple: expanding ring from entry point
			float rd = length(uv - uRipplePos);
			float ring = uRipple * exp(-uRippleT*1.8) * sin(rd*28.0 - uRippleT*14.0) * exp(-rd*2.5);
			float a = ang + 0.45*(1.0-r) + t*0.08;
			vec2 swuv = vec2(cos(a),sin(a))*(r*7.5) + ring*0.35;
			vec2 q = vec2(fbm(swuv + t*0.35), fbm(swuv + vec2(5.2,1.3) - t*0.35));
			float n = fbm(swuv + 0.6*q + vec2(t*0.25, -t*0.18));
			// SGU look: blue water with hard white caustic blobs
			float n2 = fbm(swuv*2.3 + q*0.8 - vec2(t*0.3, t*0.2));
			float caustic = (smoothstep(0.50, 0.56, n) * 0.7 + smoothstep(0.56, 0.62, n2) * 0.6) * (0.5 + 0.5*smoothstep(0.95, 0.2, r));
			float core = smoothstep(0.7, 0.0, r);
			float body = 1.0 - smoothstep(0.90, 1.0, r);
			vec3 col = mix(edgeColor, midColor, clamp((n*0.9+0.25)*1.3,0.0,1.0));
			col = mix(col, coreColor, clamp(caustic*(0.7+core*0.6),0.0,1.0));
			col += coreColor * core * 0.12 * (0.6+n);
			col *= body * 1.45 + 0.05;
			gl_FragColor = vec4(col, 1.0);
		}`,
};

const metal = (c, rough = 0.55, metalness = 0.75) => new THREE.MeshStandardMaterial({ color: c, roughness: rough, metalness });

export const createStargate = () => {
	const g = new THREE.Group();
	g.name = 'stargate';
	const { rOuter, rInner, chevrons } = GATE;
	const ringW = rOuter - rInner;

	const ringMat = metal(0x34332f, 0.5, 0.8);
	const bandMat = metal(0x2b2a27, 0.7, 0.6);
	const trimMat = metal(0x8a7a5c, 0.4, 0.9); // bronze highlights

	// Outer body: flattened torus-like ring built from a cylinder shell (crisp faces like the reference)
	const ringGroup = new THREE.Group(); ringGroup.name = 'ringGroup'; g.add(ringGroup);
	const ring = new THREE.Mesh(new THREE.CylinderGeometry(rOuter, rOuter, 0.55, 96, 1, true), ringMat);
	ring.rotation.x = Math.PI / 2; ringGroup.add(ring);
	const inner = new THREE.Mesh(new THREE.CylinderGeometry(rInner, rInner, 0.55, 96, 1, true), bandMat);
	inner.rotation.x = Math.PI / 2; inner.material.side = THREE.BackSide; ringGroup.add(inner);
	for (const z of [-0.275, 0.275]) {
		const face = new THREE.Mesh(new THREE.RingGeometry(rInner, rOuter, 96), ringMat);
		face.position.z = z; if (z < 0) face.rotation.y = Math.PI; ringGroup.add(face);
		// glyph band: thin dark groove + bronze rim
		const groove = new THREE.Mesh(new THREE.RingGeometry(rInner + ringW * 0.42, rInner + ringW * 0.58, 96), bandMat);
		groove.position.z = z + Math.sign(z) * 0.004; if (z < 0) groove.rotation.y = Math.PI; ringGroup.add(groove);
		for (const rr of [rInner + 0.06, rOuter - 0.06]) {
			const rim = new THREE.Mesh(new THREE.RingGeometry(rr - 0.03, rr + 0.03, 96), trimMat);
			rim.position.z = z + Math.sign(z) * 0.006; if (z < 0) rim.rotation.y = Math.PI; ringGroup.add(rim);
		}
	}
	// glyph ticks around band (36 of them)
	const tickGeo = new THREE.BoxGeometry(0.05, ringW * 0.12, 0.02);
	for (let i = 0; i < 36; i++) {
		const a = (i / 36) * Math.PI * 2;
		for (const z of [-0.29, 0.29]) {
			const t = new THREE.Mesh(tickGeo, trimMat);
			t.position.set(Math.cos(a) * (rInner + ringW * 0.5), Math.sin(a) * (rInner + ringW * 0.5), z);
			t.rotation.z = a - Math.PI / 2; ringGroup.add(t);
		}
	}

	// Chevrons: bracket block + cyan V light (identity-defining detail from the reference)
	const chevMat = metal(0x2c2b27, 0.45, 0.85);
	const makeGlow = () => new THREE.MeshStandardMaterial({ color: 0x1fb8d8, emissive: 0x18a6c8, emissiveIntensity: 0.0, roughness: 0.3 });
	const glowMats = [];
	const chevronPivots = [];
	const vShape = new THREE.Shape();
	vShape.moveTo(-0.13, 0.2); vShape.lineTo(0.13, 0.2); vShape.lineTo(0.0, -0.14); vShape.lineTo(-0.13, 0.2);
	const vGeo = new THREE.ExtrudeGeometry(vShape, { depth: 0.03, bevelEnabled: false });
	for (let i = 0; i < chevrons; i++) {
		const a = Math.PI / 2 - (i / chevrons) * Math.PI * 2;
		const pivot = new THREE.Group();
		pivot.rotation.z = a - Math.PI / 2;
		const glowMat = makeGlow(); glowMats.push(glowMat);
		const bracket = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.55, 0.66), chevMat);
		bracket.position.y = rOuter - 0.02; pivot.add(bracket);
		const cap = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.16, 0.74), chevMat);
		cap.position.y = rOuter + 0.32; pivot.add(cap);
		for (const z of [0.34, -0.37]) {
			const v = new THREE.Mesh(vGeo, glowMat);
			v.position.set(0, rOuter - 0.05, z); pivot.add(v);
		}
		g.add(pivot); chevronPivots.push(pivot);
	}

	// Event horizon (opaque, covers whatever is behind — see gdshader note)
	const horizonMat = new THREE.ShaderMaterial({ ...horizonShader, uniforms: THREE.UniformsUtils.clone(horizonShader.uniforms) });
	const horizon = new THREE.Mesh(new THREE.CircleGeometry(rInner - 0.02, 96), horizonMat);
	horizon.material.side = THREE.DoubleSide;
	horizon.name = 'eventHorizon'; horizon.visible = false; g.add(horizon);
	// Kawoosh plume: bulbous vortex erupting toward +Z (the viewer), widest at the gate, rounded tip ~4.5 m out.
	// Lathe profile (radius vs. length) + swirl shader (rotating streaks, tip/rim fade). Mirrors stargate.gd kawoosh().
	const PLUME_LEN = 4.6;
	const profile = [];
	for (let i = 0; i <= 24; i++) {
		const k = i / 24; // 0 = gate plane, 1 = tip
		const rad = (rInner - 0.25) * Math.pow(Math.sin(Math.PI * (0.5 + 0.5 * k)), 0.7) * (1 - 0.22 * k) + 0.001;
		profile.push(new THREE.Vector2(i === 24 ? 0.001 : rad, k * PLUME_LEN));
	}
	const plumeMat = new THREE.ShaderMaterial({
		transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide,
		uniforms: { uTime: { value: 0 }, uFade: { value: 1 } },
		vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
		fragmentShader: `
			precision highp float; varying vec2 vUv; uniform float uTime, uFade;
			float hash21(vec2 p){ p = fract(p*vec2(123.34,456.21)); p += dot(p,p+45.32); return fract(p.x*p.y); }
			float vnoise(vec2 p){ vec2 i=floor(p), f=fract(p); vec2 u=f*f*(3.0-2.0*f);
				return mix(mix(hash21(i),hash21(i+vec2(1,0)),u.x), mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),u.x), u.y); }
			void main(){
				float ang = vUv.x * 6.2831853;           // around the plume
				float len = vUv.y;                       // 0 gate → 1 tip
				// helical streaks racing outward + twisting: the vortex read
				float streak = pow(sin(ang * 6.0 + len * 16.0 - uTime * 24.0) * 0.5 + 0.5, 2.5);
				float n = vnoise(vec2(ang * 1.6 + uTime * 1.5, len * 5.0 - uTime * 6.0));
				float v = streak * 0.9 + n * 0.55;
				float tip = 1.0 - smoothstep(0.75, 1.0, len);   // fade into the rounded tip
				float base = smoothstep(0.0, 0.08, len);        // no hard seam at the gate plane
				vec3 col = mix(vec3(0.25, 0.7, 1.0), vec3(0.85, 0.97, 1.0), smoothstep(0.55, 0.95, v));
				gl_FragColor = vec4(col * (0.35 + v), (0.18 + v * 0.55) * tip * base * uFade);
			}`,
	});
	const plume = new THREE.Mesh(new THREE.LatheGeometry(profile, 64), plumeMat);
	plume.rotation.x = Math.PI / 2; // lathe axis +Y → +Z (out of the gate toward the viewer)
	const plumeCore = new THREE.Mesh(new THREE.LatheGeometry(profile.map((v) => new THREE.Vector2(v.x * 0.55, v.y * 0.92)), 48), plumeMat);
	plumeCore.rotation.x = Math.PI / 2;
	const plumePivot = new THREE.Group(); plumePivot.add(plume, plumeCore); plumePivot.scale.set(0, 0, 0); plumePivot.visible = false; g.add(plumePivot);

	// Cyan spill light from the puddle
	const spill = new THREE.PointLight(0x4fb8ff, 0, 22, 1.6);
	spill.position.set(0, 0, 1.6); g.add(spill);

	g.userData.sockets = { horizon, spill, chevronPivots, ringGroup, plumePivot };
	g.userData.active = false;
	// Dialing sequence: ring spins, each chevron locks with a flash, kawoosh erupts, horizon forms.
	// onEvent(name, index) → 'chevron' | 'kawoosh' | 'active' (caller plays sounds).
	let dial = null;
	g.userData.dial = (onEvent) => { dial = { t: 0, locked: 0, spin: 0, onEvent }; };
	// Incoming wormhole: chevrons already locked, jump straight to the kawoosh.
	g.userData.incoming = (onEvent) => { dial = { t: KAWOOSH_AT - 0.05, locked: chevrons, spin: 0, onEvent }; for (const m of glowMats) m.emissiveIntensity = 1.4; };
	let closing = 0; // >0 while the horizon collapses
	g.userData.shutdown = () => { if (!g.userData.active) return; g.userData.active = false; closing = 0.45; };
	g.userData.reset = () => { dial = null; closing = 0; horizon.scale.set(1, 1, 1); g.userData.active = false; horizon.visible = false; plumePivot.visible = false; spill.intensity = 0; horizonMat.uniforms.uRipple.value = 0; };
	const CHEV_INTERVAL = 0.55, KAWOOSH_AT = 0.4 + CHEV_INTERVAL * chevrons + 0.35;
	g.userData.colliders = []; // filled by caller after placement (ring halves)
	g.userData.tick = (t, dt) => {
		horizonMat.uniforms.uTime.value = t;
		if (horizonMat.uniforms.uRipple.value > 0) horizonMat.uniforms.uRippleT.value += dt;
		// chevron glow decay back to steady state
		for (let i = 0; i < glowMats.length; i++) {
			const m = glowMats[i]; const steady = (dial && i < dial.locked) || g.userData.active ? 1.4 : 0.0;
			m.emissiveIntensity += (steady - m.emissiveIntensity) * Math.min(1, dt * 6);
		}
		if (g.userData.active) spill.intensity = 55 + Math.sin(t * 2.3) * 6 + Math.sin(t * 7.1) * 3;
		if (closing > 0) {
			closing = Math.max(0, closing - dt);
			const k = closing / 0.45; // 1 → 0
			horizon.scale.set(k, k, 1); spill.intensity = 55 * k;
			if (closing === 0) { horizon.visible = false; horizon.scale.set(1, 1, 1); }
		}
		if (!dial) return;
		dial.t += dt;
		// ring spin: accelerate, hold, brake to a stop at the last chevron
		const spinEnd = 0.4 + CHEV_INTERVAL * chevrons;
		const spinK = dial.t < spinEnd ? THREE.MathUtils.smoothstep(dial.t, 0, 0.9) * (1 - THREE.MathUtils.smoothstep(dial.t, spinEnd - 0.6, spinEnd)) : 0;
		ringGroup.rotation.z += spinK * 1.6 * dt;
		// chevron locks
		const due = Math.floor((dial.t - 0.4) / CHEV_INTERVAL) + 1;
		while (dial.locked < Math.min(chevrons, Math.max(0, due))) {
			const i = dial.locked++;
			glowMats[i].emissiveIntensity = 4.5;
			chevronPivots[i].userData.kick = 1;
			dial.onEvent?.('chevron', i);
		}
		for (const p of chevronPivots) if (p.userData.kick > 0) { p.userData.kick = Math.max(0, p.userData.kick - dt * 5); p.position.setFromCylindricalCoords(0.12 * Math.sin(p.userData.kick * Math.PI), p.rotation.z + Math.PI / 2, 0); }
		// kawoosh
		const kt = dial.t - KAWOOSH_AT;
		if (kt >= 0 && !dial.kawooshed) { dial.kawooshed = true; plumePivot.visible = true; horizon.visible = true; dial.onEvent?.('kawoosh'); }
		if (dial.kawooshed) {
			let sc, fade = 1;
			if (kt < 0.3) sc = THREE.MathUtils.smoothstep(kt / 0.3, 0, 1) * 1.05;
			else if (kt < 0.75) sc = 1.05 - 0.08 * Math.sin((kt - 0.3) * 14.0);
			else { const u = Math.min(1, (kt - 0.75) / 0.45); sc = (1 - u * u) * 1.0; fade = 1 - u * 0.6; }
			plumePivot.scale.set(0.8 + 0.2 * sc, 0.8 + 0.2 * sc, Math.max(0.01, sc)); // radial nearly full, length drives eruption/retract
			plumeMat.uniforms.uTime.value = t; plumeMat.uniforms.uFade.value = fade * Math.min(1, sc * 3);
			spill.intensity = 40 + 320 * Math.max(0, sc);
			if (kt > 1.2) { plumePivot.visible = false; g.userData.active = true; dial.onEvent?.('active'); dial = null; }
		}
	};
	g.userData.ripple = (localX, localY) => {
		horizonMat.uniforms.uRipple.value = 1; horizonMat.uniforms.uRippleT.value = 0;
		horizonMat.uniforms.uRipplePos.value.set(localX / rInner, localY / rInner);
	};
	return g;
};
