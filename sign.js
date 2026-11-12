const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const KEY_FILE = path.join(os.homedir(), '.plugin-signing', 'ed25519.pem');
const PLUGINS = path.join(__dirname, 'plugins');
const FILE_TYPES = new Set(['.lua', '.json', '.js', '.css']);

function init() {
  if (fs.existsSync(KEY_FILE)) throw new Error(`${KEY_FILE} already exists`);
  const { privateKey, publicKey } = crypto.generateKeyPairSync('ed25519');
  fs.mkdirSync(path.dirname(KEY_FILE), { recursive: true });
  fs.writeFileSync(KEY_FILE, privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
  console.log(`Private key: ${KEY_FILE} (back it up somewhere offline)`);
  console.log(publicKey.export({ type: 'spki', format: 'pem' }));
}

function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function plugin(id) {
  const dir = path.join(PLUGINS, id);
  const files = {};
  for (const name of fs.readdirSync(dir).sort()) {
    if (!FILE_TYPES.has(path.extname(name)) || name === 'config.json') throw new Error(`plugins/${id}/${name} cannot be published`);
    files[name] = sha256(path.join(dir, name));
  }
  const manifest = JSON.parse(fs.readFileSync(path.join(dir, 'plugin.json'), 'utf8'));
  if (manifest.id !== id) throw new Error(`plugins/${id}/plugin.json declares id ${manifest.id}`);
  return { id, version: manifest.version, files };
}

function sign() {
  const key = crypto.createPrivateKey(fs.readFileSync(KEY_FILE));
  const ids = fs.readdirSync(PLUGINS, { withFileTypes: true }).filter((entry) => entry.isDirectory()).map((entry) => entry.name).sort();
  const index = `${JSON.stringify({ signed: new Date().toISOString(), plugins: ids.map(plugin) }, null, 2)}\n`;
  fs.writeFileSync(path.join(__dirname, 'index.json'), index);
  fs.writeFileSync(path.join(__dirname, 'index.json.sig'), `${crypto.sign(null, Buffer.from(index), key).toString('base64')}\n`);
  console.log(`Signed ${ids.length} plugins: ${ids.join(', ')}`);
}

if (process.argv[2] === 'init') init();
else sign();
