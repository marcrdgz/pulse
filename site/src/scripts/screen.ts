import { splitCombo } from './keys';

// Drives the Screen mock: which space is showing and which scene plays over it.
// Visibility is all CSS, keyed off `data-space` and `data-scene` on the screen element.
export type Scene = '' | 'command' | 'collapsed' | 'drag' | 'import';

const query = 'git';
const completedRest = 'hub.com/marcrdgz/pulse';
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
const typingTimers = new WeakMap<HTMLElement, number>();

export function showSpace(screen: HTMLElement, space: string) {
  screen.dataset.space = space;
}

export function showScene(screen: HTMLElement, scene: Scene) {
  window.clearInterval(typingTimers.get(screen));
  screen.dataset.scene = scene;
  if (scene === 'command') typeQuery(screen);
}

// Flashes the keys of a shortcut over the screen, like a keystroke visualiser.
export function showKeystroke(screen: HTMLElement, combo: string) {
  const overlay = screen.querySelector<HTMLElement>('[data-keystroke]');
  if (!overlay) return;
  overlay.replaceChildren(
    ...splitCombo(combo).map((key) => {
      const cap = document.createElement('kbd');
      cap.textContent = key;
      return cap;
    }),
  );
  // Restart the animation even when the same combo repeats.
  overlay.classList.remove('shown');
  void overlay.offsetWidth;
  overlay.classList.add('shown');
}

// Replays typing "git" into the command bar until inline completion fills in the rest.
function typeQuery(screen: HTMLElement) {
  const typed = screen.querySelector<HTMLElement>('[data-typed]')!;
  const completion = screen.querySelector<HTMLElement>('[data-completion]')!;
  const finish = () => {
    typed.textContent = query;
    completion.textContent = completedRest;
    screen.dataset.completed = '';
  };

  delete screen.dataset.completed;
  if (reduceMotion.matches) return finish();

  typed.textContent = '';
  completion.textContent = '';
  let typedLength = 0;
  const timer = window.setInterval(() => {
    typedLength += 1;
    typed.textContent = query.slice(0, typedLength);
    if (typedLength === query.length) {
      window.clearInterval(timer);
      finish();
    }
  }, 160);
  typingTimers.set(screen, timer);
}
