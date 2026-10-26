/// Function bodies for `callAsyncJavaScript`, run in the agent's own content world. `read` keeps the
/// page's numbered elements there, so `point`, `press` and `fill` refer to what the agent last saw.
enum AgentScripts {
    private static let elementAtIndex = #"""
        const el = window.pulseAgentElements?.[index - 1];
        if (!el || !el.isConnected) return { error: `Element ${index} isn't on the page any more; call read_page again.` };
        """#

    private static let labelOf = #"""
        const labelOf = el => {
          const isButton = ['submit', 'button', 'reset'].includes(el.type);
          const text = el.getAttribute('aria-label') || el.labels?.[0]?.innerText || el.innerText || el.placeholder
            || el.title || el.alt || el.querySelector?.('img[alt]')?.alt || (isButton ? el.value : '') || el.name || '';
          return text.replace(/\s+/g, ' ').trim().slice(0, 80);
        };
        """#

    static let read = labelOf + #"""
        const selector = 'a[href], button, input:not([type=hidden]), textarea, select, summary, [role=button], [role=link], '
          + '[role=checkbox], [role=tab], [role=menuitem], [role=option], [contenteditable]:not([contenteditable=false])';
        const isVisible = el => el.getClientRects().length > 0 && getComputedStyle(el).visibility !== 'hidden';
        const kindOf = el => {
          const tag = el.tagName.toLowerCase(), role = el.getAttribute('role');
          if (role) return role;
          if (tag === 'a') return 'link';
          if (tag === 'input') return ['submit', 'button', 'reset', 'image'].includes(el.type) ? 'button' : `${el.type} field`;
          if (tag === 'textarea' || el.isContentEditable) return 'text area';
          if (tag === 'select') return 'menu';
          return tag;
        };
        const elements = [...document.querySelectorAll(selector)].filter(isVisible).slice(0, 300);
        window.pulseAgentElements = elements;
        const lines = elements.map((el, i) => {
          let line = `[${i + 1}] ${kindOf(el)} "${labelOf(el)}"`;
          if (el.tagName === 'A') line += ` → ${el.href}`;
          // Password values never leave the page.
          if ((el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && el.type !== 'password' && el.value
              && !['submit', 'button', 'reset', 'checkbox', 'radio'].includes(el.type)) line += ` = "${el.value.slice(0, 120)}"`;
          if (el.type === 'checkbox' || el.type === 'radio') line += el.checked ? ' (checked)' : ' (unchecked)';
          if (el.tagName === 'SELECT') line += ` = "${el.selectedOptions[0]?.text.trim() ?? ''}"`;
          if (el.disabled) line += ' (disabled)';
          return line;
        });
        const text = document.body?.innerText ?? '';
        return { title: document.title, url: location.href, elements: lines,
                 text: text.length > 20000 ? text.slice(0, 20000) + '\n[…cut]' : text };
        """#

    /// Glides the agent's pointer, named after it, onto the element, so the user sees what it's about to do.
    static let point = elementAtIndex + labelOf + #"""
        el.scrollIntoView({ block: 'center', behavior: 'smooth' });
        await new Promise(resolve => setTimeout(resolve, 400));
        let pointer = document.getElementById('pulse-agent-pointer');
        if (!pointer) {
          pointer = document.createElement('div');
          pointer.id = 'pulse-agent-pointer';
          pointer.style.cssText = 'position:fixed;left:0;top:0;z-index:2147483647;pointer-events:none;'
            + `transition:transform .5s cubic-bezier(.3,.7,.2,1);transform:translate(${innerWidth / 2}px,${innerHeight / 2}px)`;
          const shadow = pointer.attachShadow({ mode: 'closed' });
          shadow.innerHTML = `<style>
              svg { display: block; filter: drop-shadow(0 1px 2px rgba(0,0,0,.35)); }
              span { position: absolute; left: 16px; top: 18px; padding: 2px 7px; border-radius: 9px; white-space: nowrap;
                     font: 600 11px -apple-system, system-ui; color: white; background: #7b4dff; }
            </style>
            <svg width="20" height="22" viewBox="0 0 20 22"><path d="M2 2v15l4.2-3.8 2.8 6.6 2.6-1.1-2.8-6.5H15z"
              fill="#7b4dff" stroke="white" stroke-width="1.5" stroke-linejoin="round"/></svg><span></span>`;
          shadow.querySelector('span').textContent = name;
          document.documentElement.append(pointer);
          pointer.getBoundingClientRect();
        }
        const rect = el.getBoundingClientRect();
        pointer.style.transform = `translate(${rect.left + Math.min(rect.width / 2, 100)}px,${rect.top + rect.height / 2}px)`;
        await new Promise(resolve => setTimeout(resolve, 550));
        return { label: labelOf(el) || el.tagName.toLowerCase() };
        """#

    static let press = elementAtIndex + #"""
        el.focus?.({ preventScroll: true });
        el.click();
        return {};
        """#

    /// Sets the value through the element's own setter and fires `input`, so frameworks that track
    /// the value (React) see the change as if typed.
    static let fill = elementAtIndex + #"""
        if (el.type === 'password') return { error: "Agents can't type passwords in Pulse. Ask the user to sign in." };
        el.focus();
        if (el.tagName === 'SELECT') {
          const option = [...el.options].find(o => o.text.trim() === text || o.value === text);
          if (!option) return { error: `No option "${text}". The options are: ${[...el.options].map(o => o.text.trim()).join(', ')}` };
          el.value = option.value;
        } else if (el.isContentEditable) {
          document.execCommand('selectAll');
          document.execCommand('insertText', false, text);
        } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
          const prototype = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
          Object.getOwnPropertyDescriptor(prototype, 'value').set.call(el, text);
        } else {
          return { error: `Element ${index} isn't a field.` };
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
        return {};
        """#

    static let hidePointer = "document.getElementById('pulse-agent-pointer')?.remove(); return {};"
}
