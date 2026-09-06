// Asset root: dev serves from the repo (../../models, ../../sounds, ../../data); the itch.io build sets
// window.__ASSET_ROOT = './assets/' in index.html and copies the referenced files under dist/assets/.
export const ASSETS = window.__ASSET_ROOT ?? '../../';
