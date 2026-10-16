// ESLint flat config for Stargate Universe — web/Three.js ES modules.
// Minimal rules: catch real bugs (unused vars, no-debugger) without fighting style.
export default [
	{
		files: ['src/**/*.js', 'tests/**/*.js'],
		languageOptions: {
			ecmaVersion: 2024,
			sourceType: 'module',
			globals: {
				window: 'readonly',
				document: 'readonly',
				localStorage: 'readonly',
				location: 'readonly',
				navigator: 'readonly',
				performance: 'readonly',
				requestAnimationFrame: 'readonly',
				cancelAnimationFrame: 'readonly',
				setTimeout: 'readonly',
				clearTimeout: 'readonly',
				setInterval: 'readonly',
				clearInterval: 'readonly',
				console: 'readonly',
				addEventListener: 'readonly',
				innerWidth: 'readonly',
				innerHeight: 'readonly',
				THREE: 'readonly',
			},
		},
		rules: {
			'no-unused-vars': ['warn', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
			'no-debugger': 'error',
			'no-console': ['warn', { allow: ['warn', 'error'] }],
			'no-undef': 'off', // checkJs + tsc handles this better than eslint for browser globals
			'prefer-const': 'warn',
			'no-constant-condition': 'warn',
		},
	},
	{
		ignores: ['node_modules/', 'dist/', 'build/', '*.py', 'tools/vendor.py'],
	},
];