const SERVER = 'https://oblak.moma.rs';
const $ = id => document.getElementById(id);

const segment = window.location.pathname.split('/')[2];
if (segment) {
  $('lambda-id').value = segment;
}

function setStatus(msg, type) {
  const el = $('status');
  el.textContent = msg;
  el.className = 'status ' + type;
}

async function invoke() {
  const lambdaId = $('lambda-id').value.trim();
  const input    = $('input').value;

  if (!lambdaId) return setStatus('Lambda ID is required.', 'err');

  const btn = $('invoke-btn');
  btn.disabled = true;
  btn.textContent = 'Invoking…';
  $('output').value = '';
  $('status').className = 'status';

  try {
    const resp = await fetch(`${SERVER}/lambdas/${lambdaId}/invoke`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ input }),
    });

    const data = await resp.json();

    if (!resp.ok) {
      setStatus(data.error || `HTTP ${resp.status}`, 'err');
      return;
    }

    $('output').value = data.output ?? '';

    if (data.exit_code !== 0) {
      setStatus(`Exit code ${data.exit_code}${data.stderr ? ' — ' + data.stderr.trim() : ''}`, 'err');
    } else if (data.stderr) {
      setStatus(`stderr: ${data.stderr.trim()}`, 'err');
    } else {
      setStatus('OK', 'ok');
    }

  } catch (err) {
    setStatus(`Network error: ${err.message}`, 'err');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Invoke';
  }
}