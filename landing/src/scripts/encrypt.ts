// Hero demo: type plaintext, watch the "what our server sees" line re-encrypt
// with a staggered scramble. Uses the real "3:" PreKey envelope prefix.
import { autoGrow, B64, rnd } from './util';

export function initEncrypt(root: HTMLElement) {
  root.innerHTML = `
    <label>Type something private</label>
    <textarea rows="1" spellcheck="false" autocomplete="off" placeholder="sending very sensitive data…" maxlength="120"></textarea>
    <div class="server-line">
      <span class="server-tag">what our server sees</span>
      <code class="cipher"></code>
    </div>`;
  const input = root.querySelector('textarea')!;
  const cipher = root.querySelector('.cipher')!;
  const spans: { el: HTMLSpanElement; final: string; settleAt: number }[] = [];

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
  (function frame() {
    const now = performance.now();
    for (const s of spans) {
      if (s.settleAt > now) { s.el.textContent = rnd(B64); s.el.className = 'hot'; }
      else if (s.el.className !== 'cold') { s.el.textContent = s.final; s.el.className = 'cold'; }
    }
    requestAnimationFrame(frame);
  })();
  // a long message wraps and the box grows with it — never scrolls out of
  // view (single logical line: Enter is swallowed, pasted newlines become
  // spaces before anything downstream sees the value)
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') e.preventDefault(); });
  input.addEventListener('input', () => {
    if (input.value.includes('\n')) input.value = input.value.replace(/\n+/g, ' ');
    autoGrow(input);
    setLen(input.value.length);
    const now = performance.now();
    for (let i = 2; i < spans.length; i++) {
      spans[i].final = rnd(B64);
      spans[i].settleAt = now + 120 + Math.random() * 520;
    }
    // feed the journey: whatever the visitor types here becomes the draft
    // on the sender phone (until they type there directly)
    document.dispatchEvent(new CustomEvent('fp:plain', { detail: input.value }));
  });
  // journey top-reverse clears this demo too — never stomps active typing
  document.addEventListener('fp:clear', () => {
    if (document.activeElement === input) return;
    input.value = '';
    autoGrow(input);
    setLen(0);
  });
  setLen(0);
}
