'use strict';

(function () {
  const logEl = document.getElementById('log');

  function log(line) {
    logEl.textContent += `${line}\n`;
    logEl.scrollTop = logEl.scrollHeight;
  }

  async function fetchJsonLogged(url, init = {}) {
    const headers = { Accept: 'application/json', ...init.headers };
    const next = { ...init, headers };
    const bodyNote = init.body ? `\n  ${init.body}` : '';
    log(`→ ${init.method || 'GET'} ${url}${bodyNote}`);

    const res = await fetch(url, next);
    const text = await res.text();
    let pretty = '(empty)';
    if (text) {
      try {
        pretty = JSON.stringify(JSON.parse(text), null, 2);
      } catch {
        pretty = text;
      }
    }
    log(`← ${res.status} ${res.statusText}\n${pretty}\n`);
    return { res, text };
  }

  function postAsForm(url, form) {
    return fetchJsonLogged(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' },
      body: new URLSearchParams(new FormData(form)).toString(),
    });
  }

  function parseId() {
    const raw = document.getElementById('ipId').value.trim();
    const id = parseInt(raw, 10);
    if (!raw || !Number.isFinite(id) || id < 1) {
      window.alert('Enter a positive numeric id.');
      return null;
    }
    return id;
  }

  function pad2(n) {
    return String(n).padStart(2, '0');
  }

  function toDatetimeLocalValue(date) {
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())}T${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }

  function setDefaultStatsRange() {
    const now = new Date();
    document.getElementById('timeFrom').value = toDatetimeLocalValue(new Date(now - 3600000));
    document.getElementById('timeTo').value = toDatetimeLocalValue(now);
  }

  const formCreate = document.getElementById('formCreate');
  const enabledHidden = formCreate.querySelector('[name="enabled"]');
  formCreate.querySelector('#f-enabled-cb').addEventListener('change', (e) => {
    enabledHidden.value = e.target.checked ? 'true' : 'false';
  });

  formCreate.addEventListener('submit', async (e) => {
    e.preventDefault();
    const { res, text } = await postAsForm('/ips', formCreate);
    if (!res.ok) return;
    try {
      const data = JSON.parse(text);
      if (data && typeof data.id === 'number') {
        document.getElementById('ipId').value = String(data.id);
      }
    } catch {
      // response was not JSON
    }
  });

  document.getElementById('btnEnable').addEventListener('click', async () => {
    const id = parseId();
    if (id != null) await fetchJsonLogged(`/ips/${id}/enable`, { method: 'POST' });
  });

  document.getElementById('btnDisable').addEventListener('click', async () => {
    const id = parseId();
    if (id != null) await fetchJsonLogged(`/ips/${id}/disable`, { method: 'POST' });
  });

  document.getElementById('btnDelete').addEventListener('click', async () => {
    const id = parseId();
    if (id != null) await fetchJsonLogged(`/ips/${id}`, { method: 'DELETE' });
  });

  document.getElementById('btnStats').addEventListener('click', async () => {
    const id = parseId();
    if (id == null) return;

    const timeFrom = document.getElementById('timeFrom').value;
    const timeTo = document.getElementById('timeTo').value;
    if (!timeFrom || !timeTo) {
      window.alert('Fill in time_from and time_to.');
      return;
    }

    const q = new URLSearchParams({
      time_from: new Date(timeFrom).toISOString(),
      time_to: new Date(timeTo).toISOString(),
    });
    await fetchJsonLogged(`/ips/${id}/stats?${q}`);
  });

  setDefaultStatsRange();
  log('Ready. Create an IP or enter an existing id.');
})();
