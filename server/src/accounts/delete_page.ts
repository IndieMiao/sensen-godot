/**
 * 站外删号页（Google Play 要求可在应用外删除账号；Apple 5.1.1(v) 的应用内删号已在 App 里）。
 *
 * 纯静态、不加载任何外部资源（CSP 只放行同源 fetch）。接口用相对路径，所以无论服务挂在
 * /v1 还是 /preview/journey/v1 下都能用。两种证明身份的方式：密码，或发到邮箱的删号验证码。
 */
export const DELETE_PAGE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<link rel="icon" href="data:,">
<title>Delete your Sensen account</title>
<style>
  :root { --ink:#232b30; --muted:#69716e; --paper:#fffdf8; --line:#e4e2d6; --lime:#cafa91; --green:#5d8f2e; --coral:#c9585b; }
  * { box-sizing: border-box; }
  body { margin:0; font:16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    color:var(--ink); background:linear-gradient(160deg,#eaf6ff 0%,#fffdf8 45%,#eef9df 100%); min-height:100vh; }
  main { max-width:440px; margin:0 auto; padding:48px 20px 64px; }
  .card { background:#fff; border:1px solid var(--line); border-radius:20px; padding:28px 24px; box-shadow:0 8px 30px rgba(35,43,48,.08); }
  h1 { font-size:24px; margin:0 0 8px; }
  p { margin:0 0 14px; color:var(--muted); }
  ul { margin:0 0 18px; padding-left:20px; color:var(--muted); }
  .tabs { display:flex; gap:8px; margin:18px 0 14px; }
  .tabs button { flex:1; border:1px solid var(--line); background:var(--paper); color:var(--ink); border-radius:999px; padding:9px; font:inherit; font-size:14px; cursor:pointer; }
  .tabs button[aria-selected="true"] { background:var(--lime); border-color:#a6dc6c; font-weight:600; }
  label { display:block; font-size:14px; font-weight:600; margin:12px 0 6px; }
  input { width:100%; font:inherit; padding:12px 14px; border:1px solid var(--line); border-radius:12px; background:var(--paper); color:var(--ink); }
  input:focus { outline:2px solid #a6dc6c; border-color:#a6dc6c; }
  .row { display:flex; gap:8px; align-items:flex-end; }
  .row > div { flex:1; }
  button.secondary { border:1px solid var(--line); background:#fff; color:var(--ink); border-radius:12px; padding:12px 14px; font:inherit; font-size:14px; cursor:pointer; white-space:nowrap; }
  .confirm { display:flex; gap:10px; align-items:flex-start; margin:18px 0 6px; font-size:14px; color:var(--ink); font-weight:400; }
  .confirm input { width:auto; margin-top:3px; }
  button.danger { width:100%; margin-top:14px; border:0; border-radius:14px; padding:14px; font:inherit; font-weight:600; color:#fff; background:var(--coral); cursor:pointer; }
  button:disabled { opacity:.55; cursor:not-allowed; }
  .status { min-height:22px; margin-top:14px; font-size:14px; }
  .status.error { color:var(--coral); } .status.ok { color:var(--green); }
  .done h1 { color:var(--green); }
  footer { text-align:center; font-size:12px; color:var(--muted); margin-top:18px; }
  [hidden] { display:none !important; }
</style>
</head>
<body>
<main>
  <div class="card" id="form-card">
    <h1>Delete your Sensen account</h1>
    <p>This permanently deletes your account. It cannot be undone.</p>
    <ul>
      <li>Your email sign-in, nickname and profile</li>
      <li>Your farm, crops, items and progress</li>
      <li>Your place in parties and shared spaces</li>
    </ul>
    <p>You can also delete your account in the app: <b>Account → Delete account</b>.</p>
    <div class="tabs" role="tablist">
      <button type="button" role="tab" id="tab-password" aria-selected="true">Use password</button>
      <button type="button" role="tab" id="tab-code" aria-selected="false">Forgot password? Use email code</button>
    </div>
    <form id="delete-form" autocomplete="on">
    <label for="email">Email</label>
    <input id="email" type="email" autocomplete="email" inputmode="email" placeholder="you@example.com">
    <div id="by-password">
      <label for="password">Password</label>
      <input id="password" type="password" autocomplete="current-password">
    </div>
    <div id="by-code" hidden>
      <div class="row">
        <div><label for="code">6-digit code</label><input id="code" inputmode="numeric" maxlength="6" autocomplete="one-time-code"></div>
        <button type="button" class="secondary" id="send-code">Send code</button>
      </div>
    </div>
    <label class="confirm"><input type="checkbox" id="confirm"> I understand my account and farm will be permanently deleted.</label>
    <button type="button" class="danger" id="delete" disabled>Delete my account</button>
    <div class="status" id="status" role="status"></div>
    </form>
  </div>
  <div class="card done" id="done-card" hidden>
    <h1>Your account has been deleted</h1>
    <p>Your account, profile and farm have been removed. You can close this page.</p>
  </div>
  <footer>Sensen · Account deletion</footer>
</main>
<script>
(function () {
  var base = location.pathname.replace(/\\/$/, '');
  var mode = 'password';
  var $ = function (id) { return document.getElementById(id); };
  var messages = {
    INVALID_EMAIL: 'Enter a valid email address.',
    INVALID_CREDENTIALS: 'Email or password is incorrect.',
    CODE_INVALID: 'That code is not right. Check the email and try again.',
    CODE_EXPIRED: 'That code has expired. Send a new one.',
    CODE_LOCKED: 'Too many wrong codes. Send a new one.',
    CODE_COOLDOWN: 'A code was just sent. Wait a minute before asking again.',
    RATE_LIMITED: 'Too many attempts. Try again later.',
    SCHEMA: 'Please fill in every field.'
  };
  function say(text, ok) { var s = $('status'); s.textContent = text; s.className = 'status ' + (ok ? 'ok' : 'error'); }
  function refresh() {
    var email = $('email').value.trim();
    var proof = mode === 'password' ? $('password').value.length > 0 : /^\\d{6}$/.test($('code').value.trim());
    $('delete').disabled = !(email && proof && $('confirm').checked);
  }
  function select(next) {
    mode = next;
    $('tab-password').setAttribute('aria-selected', String(next === 'password'));
    $('tab-code').setAttribute('aria-selected', String(next === 'code'));
    $('by-password').hidden = next !== 'password';
    $('by-code').hidden = next !== 'code';
    say('', true); refresh();
  }
  function post(url, body) {
    return fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().catch(function () { return {}; }).then(function (j) { return { ok: r.ok, body: j }; }); });
  }
  $('delete-form').addEventListener('submit', function (e) { e.preventDefault(); if (!$('delete').disabled) $('delete').click(); });
  $('tab-password').onclick = function () { select('password'); };
  $('tab-code').onclick = function () { select('code'); };
  ['email', 'password', 'code', 'confirm'].forEach(function (id) { $(id).addEventListener('input', refresh); $(id).addEventListener('change', refresh); });
  $('send-code').onclick = function () {
    var email = $('email').value.trim();
    if (!email) return say(messages.INVALID_EMAIL);
    $('send-code').disabled = true;
    post(base + '/code', { email: email }).then(function (r) {
      $('send-code').disabled = false;
      if (r.ok) say('If this email has an account, a code is on its way.', true);
      else say(messages[r.body.code] || 'Something went wrong. Please try again.');
    }).catch(function () { $('send-code').disabled = false; say('Can\\'t reach the server. Check your connection.'); });
  };
  $('delete').onclick = function () {
    var body = { email: $('email').value.trim() };
    if (mode === 'password') body.password = $('password').value; else body.code = $('code').value.trim();
    $('delete').disabled = true; say('Deleting…', true);
    post(base, body).then(function (r) {
      if (r.ok) { $('form-card').hidden = true; $('done-card').hidden = false; return; }
      say(messages[r.body.code] || 'Something went wrong. Please try again.'); refresh();
    }).catch(function () { say('Can\\'t reach the server. Check your connection.'); refresh(); });
  };
})();
</script>
</body>
</html>
`;
