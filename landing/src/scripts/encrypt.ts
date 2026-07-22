// Hero demo: type plaintext, watch the "what our server sees" line re-encrypt
// with a staggered scramble. Uses the real "3:" PreKey envelope prefix.
import { autoGrow, B64, rafOnScreen, rnd } from './util';

export function initEncrypt(root: HTMLElement) {
  root.classList.add('enc-terminal');
  root.innerHTML = `
    <div class="enc-label-row">
      <label for="terminal-plain">Plaintext · your device</label>
      <span class="enc-count">00/120</span>
    </div>
    <div class="enc-port">
      <span class="enc-prompt" aria-hidden="true">›</span>
      <span class="enc-rest-caret" aria-hidden="true"></span>
      <textarea id="terminal-plain" rows="1" spellcheck="false" autocomplete="off" placeholder="type a secret — watch it seal" maxlength="120"></textarea>
      <button class="enc-done" type="button">Done</button>
    </div>
    <div class="enc-port-rail">
      <span class="enc-status"><i></i><b>Ready</b></span>
      <span class="enc-tap">Click / tap to type</span>
    </div>
    <div class="server-line">
      <span class="server-tag">what our server sees</span>
      <code class="cipher"></code>
    </div>`;
  const input = root.querySelector('textarea')!;
  const cipher = root.querySelector('.cipher')!;
  const count = root.querySelector<HTMLElement>('.enc-count')!;
  const status = root.querySelector<HTMLElement>('.enc-status b')!;
  const port = root.querySelector<HTMLElement>('.enc-port')!;
  const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const spans: { el: HTMLSpanElement; final: string; settleAt: number }[] = [];

  input.addEventListener('focus', () => { status.textContent = 'Live'; });
  input.addEventListener('blur', () => { status.textContent = 'Ready'; });
  // Done dismisses the keyboard (mobile has no other exit — Enter is swallowed
  // to keep the box one line). It works on POINTERDOWN, not click: iOS Safari
  // only honors a programmatic blur() from inside a real touch gesture, and a
  // click on the pill with the keyboard up doesn't fire reliably. preventDefault
  // keeps the button from taking focus — otherwise Android holds
  // .enc-port:focus-within through the button itself and the pill never hides.
  // Once the pill hides mid-gesture the trailing click retargets to the port —
  // swallow it for a beat so it can't refocus the field and reopen the keyboard.
  const done = root.querySelector<HTMLButtonElement>('.enc-done')!;
  let doneAt = 0;
  port.addEventListener('click', () => {
    if (performance.now() - doneAt < 500) return;
    input.focus();
  });
  done.addEventListener('pointerdown', (e) => {
    e.preventDefault();
    e.stopPropagation();
    doneAt = performance.now();
    input.blur();
  });

  const setLen = (n: number) => {
    const total = n === 0 ? 0 : 2 + Math.ceil(n * 4 / 3) + 12;
    while (spans.length > total) spans.pop()!.el.remove();
    while (spans.length < total) {
      const el = document.createElement('span');
      const i = spans.length;
      const final = i === 0 ? '3' : i === 1 ? ':' : rnd(B64);
      el.textContent = final;
      cipher.appendChild(el);
      spans.push({ el, final, settleAt: 0 });
    }
  };
  function frame() {
    const now = performance.now();
    for (const s of spans) {
      if (s.settleAt > now) { s.el.textContent = rnd(B64); s.el.className = 'hot'; }
      else if (s.el.className !== 'cold') { s.el.textContent = s.final; s.el.className = 'cold'; }
    }
  }
  rafOnScreen(root, frame);
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); input.blur(); } });
  input.addEventListener('input', () => {
    if (input.value.includes('\n')) input.value = input.value.replace(/\n+/g, ' ');
    autoGrow(input);
    setLen(input.value.length);
    root.classList.toggle('has-value', input.value.length > 0);
    count.textContent = `${String(input.value.length).padStart(2, '0')}/120`;
    const now = performance.now();
    for (let i = 2; i < spans.length; i++) {
      spans[i].final = rnd(B64);
      spans[i].settleAt = reducedMotion ? 0 : now + 120 + Math.random() * 520;
    }
    document.dispatchEvent(new CustomEvent('fp:plain', { detail: input.value }));
  });
  document.addEventListener('fp:clear', () => {
    if (document.activeElement === input) return;
    input.value = '';
    autoGrow(input);
    setLen(0);
    root.classList.remove('has-value');
    count.textContent = '00/120';
  });
  setLen(0);
}
