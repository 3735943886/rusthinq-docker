#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ROOT
python3 - <<'PY'
import json, os, subprocess, tempfile, tomllib
from pathlib import Path
root = Path(os.environ['ROOT'])
with tempfile.TemporaryDirectory() as temp:
    base = Path(temp)
    def run(name, extra=None, dry=True, ok=True):
        data = base / name
        env = dict(os.environ, RUSTHINQ_RUNTIME_SERIES='0.2', RUSTHINQ_CONFIG_LIB=str(root/'config'), RUSTHINQ_DATA_DIR=str(data))
        if dry: env['RUSTHINQ_DRY_RUN'] = '1'
        env.update(extra or {})
        result = subprocess.run([str(root/'docker-entrypoint.sh')], env=env, capture_output=True, text=True)
        if ok: assert result.returncode == 0, result.stderr
        else: assert result.returncode != 0, result.stdout
        return data, result
    data, _ = run('default')
    cfg = tomllib.loads((data/'config.generated.toml').read_text())
    assert cfg['mqtt_bind'] == '0.0.0.0:8883'
    assert cfg['thinq1_bind'] == '0.0.0.0:47878'
    assert cfg['external_mqtt']['port'] == 1883
    assert cfg['drivers']['directory'] == '/scripts'
    assert cfg['management']['gui'] and cfg['legacy_tls']
    assert not (data/'ca.key').exists(), 'dry run created CA'
    data, _ = run('ipv6', {'RUSTHINQ_MQTT_URL':'mqtts://[::1]:8884', 'RUSTHINQ_MQTT_USER':'user', 'RUSTHINQ_MQTT_PASSWORD':'한글"\\\n', 'RUSTHINQ_GUI':'false'})
    cfg = tomllib.loads((data/'config.generated.toml').read_text())
    assert cfg['external_mqtt']['host'] == '::1' and cfg['external_mqtt']['tls']
    assert cfg['external_mqtt']['password'] == '한글"\\\n'
    assert not cfg['management']['gui']
    data, _ = run('off', {'RUSTHINQ_MQTT_URL':'', 'RUSTHINQ_MANAGEMENT':'false', 'RUSTHINQ_BRIDGE':'false', 'RUSTHINQ_SCRIPTING':'false'})
    cfg = tomllib.loads((data/'config.generated.toml').read_text())
    assert not set(cfg) & {'external_mqtt', 'management', 'drivers', 'cloud_account'}
    options = base/'options.json'
    options.write_text(json.dumps({'mqtt_url':'mqtt://broker:1884', 'gui_user':'admin', 'gui_password':'secret', 'bridge_dns':''}))
    config_dir = base/'ha-config'; config_dir.mkdir()
    data, _ = run('ha', {'RUSTHINQ_LOAD_OPTIONS':'true', 'RUSTHINQ_OPTIONS_FILE':str(options), 'RUSTHINQ_CONFIG_DIR':str(config_dir)})
    cfg = tomllib.loads((data/'config.generated.toml').read_text())
    example = tomllib.loads((config_dir/'config.toml.example').read_text())
    assert cfg['external_mqtt']['host'] == 'broker' and cfg['external_mqtt']['port'] == 1884
    assert cfg['drivers']['directory'] == '/config/scripts'
    assert cfg['bridge_dns'] == []
    assert example['ca_key'] == str(data/'ca.key')
    assert example['management']['password'] == 'secret'
    for url in ['http://localhost', 'mqtt://host:70000', 'mqtt://user:pass@host', 'mqtt://host/path', 'mqtt://::1']:
        run('bad-url', {'RUSTHINQ_MQTT_URL':url}, ok=False)
    run('removed', {'RUSTHINQ_RAW_PREFIX':'old'}, ok=False)
    legacy = base/'legacy'; legacy.mkdir(); (legacy/'config.generated.toml').write_text('ca_key_file = "ca.key"\n')
    _, result = run('legacy', ok=False)
    assert 'legacy generated config' in result.stderr
    assert (legacy/'config.generated.toml').read_text() == 'ca_key_file = "ca.key"\n'
    bin_dir = base/'bin'; bin_dir.mkdir()
    daemon = bin_dir/'rusthinq'; daemon.write_text('#!/bin/sh\nexit 0\n'); daemon.chmod(0o755)
    extra = {'PATH':str(bin_dir)+':'+os.environ['PATH'], 'RUSTHINQ_SCRIPTS_DIR':str(base/'scripts')}
    data, _ = run('fresh', extra, dry=False)
    key, cert = (data/'ca.key').read_bytes(), (data/'ca.cert').read_bytes()
    assert (data/'ca.key').stat().st_mode & 0o777 == 0o600
    run('fresh', extra, dry=False)
    assert (data/'ca.key').read_bytes() == key and (data/'ca.cert').read_bytes() == cert
    subprocess.run(['openssl','verify','-CAfile',str(data/'ca.cert'),str(data/'ca.cert')], check=True, capture_output=True)
    (data/'ca.cert').unlink()
    _, result = run('fresh', extra, dry=False, ok=False)
    assert 'incomplete CA' in result.stderr
    assert (data/'ca.key').read_bytes() == key
    custom = base/'custom'; custom.mkdir(); (custom/'config.toml').write_text('ca_key_file="old.key"\n')
    _, result = run('custom', extra, dry=False, ok=False)
    assert '0.1 config detected' in result.stderr
print('0.2 entrypoint tests passed')
PY
