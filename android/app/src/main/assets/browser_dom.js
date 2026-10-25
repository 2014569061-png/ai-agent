// Evaluated only by the host. No JavaScript-to-native interface is installed.
(function(request) {
  'use strict';
  const key = '__nexusBrowserObservation';
  const limits = {nodes: 8000, scannedText: 24000, text: 12000, controls: 120, depth: 64};
  const prefix = (s, n) => {
    let end = Math.min(s.length, Math.max(0, n));
    if (end > 0 && end < s.length && /[\uD800-\uDBFF]/.test(s[end - 1]) &&
        /[\uDC00-\uDFFF]/.test(s[end])) end--;
    return s.slice(0, end);
  };
  // Bound input before regex processing, including labels and attributes.
  const clip = (s, n) => prefix(prefix(String(s || ''), n * 4)
    .replace(/\s+/g, ' ').trim(), n);
  const hiddenAcrossRoots = el => {
    let current = el;
    for (let depth = 0; current && depth <= limits.depth; depth++) {
      if (current.hasAttribute('hidden') || current.hasAttribute('inert') ||
          current.getAttribute('aria-hidden') === 'true') return true;
      const root = current.getRootNode();
      current = current.parentElement || (root && root.host) || null;
    }
    return !!current; // Too deep to prove visibility: fail closed.
  };
  const visible = el => {
    const r = el.getBoundingClientRect(), s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && r.bottom > 0 && r.right > 0 &&
      r.top < innerHeight && r.left < innerWidth && s.visibility !== 'hidden' &&
      s.display !== 'none' && !hiddenAcrossRoots(el);
  };
  // Text changes are guarded by the document/shadow MutationObserver. Do not
  // construct an unbounded textContent string merely to fingerprint a node.
  const fingerprint = el => [el.tagName, ...['type', 'role', 'href', 'disabled',
    'readonly', 'aria-label'].map(name => clip(el.getAttribute(name), 1024)),
    JSON.stringify(el.getBoundingClientRect().toJSON())].join('|');
  const selector = 'a[href],button,input,textarea,select,[role="button"],[role="link"]';
  const observeOptions = {subtree: true, childList: true,
    attributes: true, characterData: true};
  const failure = code => ({ok: false, code: code});
  if (request.action === 'observe') {
    if (window[key]) window[key].observer.disconnect();
    const nodes = new Map(), fingerprints = new Map();
    const state = {snapshotId: request.snapshotId, url: location.href,
      changed: false, nodes: nodes, fingerprints: fingerprints,
      observer: new MutationObserver(() => { state.changed = true; })};
    state.observer.observe(document, observeOptions);
    window[key] = state;
    const output = [], reasons = new Set(), labels = new Map();
    const stack = [{next: document.documentElement, depth: 0, body: false,
      control: null, label: null}];
    let visited = 0, scanned = 0, text = '';
    const appendLabel = (target, value) => {
      if (target && target.text.length < 180) {
        target.text = clip(target.text + ' ' + value, 180);
      }
    };
    while (stack.length) {
      const frame = stack[stack.length - 1];
      if (!frame.next) { stack.pop(); continue; }
      if (visited >= limits.nodes) { reasons.add('node_budget'); break; }
      const node = frame.next;
      frame.next = node.nextSibling;
      visited++;
      if (node.nodeType === 3 && frame.body) {
        const raw = node.nodeValue || '';
        const remaining = limits.scannedText - scanned;
        const sample = prefix(raw, remaining);
        scanned += sample.length;
        if (sample.length < raw.length) reasons.add('text_scan_budget');
        const value = sample.replace(/\s+/g, ' ').trim();
        if (value) {
          appendLabel(frame.control, value);
          appendLabel(frame.label, value);
          const addition = (text ? ' ' : '') + value;
          const part = prefix(addition, limits.text - text.length);
          text += part;
          if (part.length < addition.length) reasons.add('text_output_budget');
        }
        continue;
      }
      if (node.nodeType !== 1 && node.nodeType !== 11) continue;
      let control = frame.control, label = frame.label;
      const element = node.nodeType === 1;
      const body = frame.body || (element && node.tagName === 'BODY');
      if (element) {
        const style = getComputedStyle(node);
        if (node.hasAttribute('hidden') || node.hasAttribute('inert') ||
            node.getAttribute('aria-hidden') === 'true' ||
            style.display === 'none' || style.visibility === 'hidden' ||
            ['SCRIPT','STYLE','TEMPLATE','NOSCRIPT','IFRAME'].includes(node.tagName)) continue;
        if (node.tagName === 'LABEL') {
          label = {text: ''}; labels.set(node, label);
        }
        if (body && node.matches(selector) && visible(node)) {
          const type = (node.getAttribute('type') || '').toLowerCase();
          if (!['password','file','hidden'].includes(type) && !node.disabled) {
            if (output.length >= limits.controls) reasons.add('control_budget');
            else {
              const id = 'n' + (output.length + 1);
              control = {text: '', element: node, entry: {
                id: id, tag: node.tagName.toLowerCase(), type: type, label: '',
                href: node.tagName === 'A' ? clip(node.href, 1024) : null,
                editable: ['INPUT','TEXTAREA'].includes(node.tagName) &&
                  !node.readOnly && ['','text','search','email','tel','url','number'].includes(type)
              }};
              nodes.set(id, node); fingerprints.set(id, fingerprint(node));
              output.push(control);
            }
          }
        }
        // Editable values are not page prose, including textarea initial text.
        if (['INPUT','TEXTAREA'].includes(node.tagName)) continue;
      }
      const shadow = element ? node.shadowRoot : null;
      if (frame.depth >= limits.depth) {
        if (node.firstChild || shadow) reasons.add('depth_budget');
        continue;
      }
      // Lazy sibling cursors: never enumerate an entire child collection first.
      if (node.firstChild) stack.push({next: node.firstChild,
        depth: frame.depth + 1, body, control, label});
      if (shadow) {
        state.observer.observe(shadow, observeOptions);
        stack.push({next: shadow, depth: frame.depth + 1, body, control, label});
      }
    }
    for (const item of output) {
      const el = item.element, associated = el.labels;
      let associatedText = '';
      // Only reuse label text already read within the shared traversal budget.
      if (associated) {
        for (let i = 0; i < Math.min(associated.length, 4); i++) {
          associatedText = clip(associatedText + ' ' + (labels.get(associated[i])?.text || ''), 180);
        }
        if (associated.length > 4) reasons.add('label_budget');
      }
      item.entry.label = clip(el.getAttribute('aria-label'), 180) ||
        associatedText || clip(el.getAttribute('placeholder'), 180) ||
        item.text || clip(el.getAttribute('title'), 180);
    }
    return {ok: true, snapshotId: request.snapshotId, url: location.href,
      title: clip(document.title, 200), text: text,
      nodes: output.map(item => item.entry), truncated: reasons.size > 0,
      truncationReasons: Array.from(reasons),
      observationBudget: {visitedNodes: visited, scannedTextChars: scanned,
        maxVisitedNodes: limits.nodes, maxScannedTextChars: limits.scannedText,
        maxDepth: limits.depth, maxTextChars: limits.text, maxControls: limits.controls},
      scope: 'bounded rendered top-level document and open shadow roots; offscreen prose may be included; frames and closed roots omitted; input values omitted',
      untrustedContent: true};
  }
  const state = window[key];
  if (!state || state.snapshotId !== request.snapshotId || state.changed ||
      state.observer.takeRecords().length || state.url !== location.href) {
    return failure('REVISION_CONFLICT');
  }
  if (request.action === 'scroll') {
    state.changed = true;
    window.scrollBy({top: request.dy, behavior: 'instant'});
    return {ok: true, dispatched: true};
  }
  const el = state.nodes.get(request.nodeId);
  if (!el || !el.isConnected || !visible(el) ||
      fingerprint(el) !== state.fingerprints.get(request.nodeId)) return failure('REVISION_CONFLICT');
  if (el.disabled || el.readOnly || ['password','file','hidden'].includes((el.type || '').toLowerCase())) {
    return failure('PERMISSION_REQUIRED');
  }
  if (request.action === 'type') {
    if (!['INPUT','TEXTAREA'].includes(el.tagName) ||
        !['','text','search','email','tel','url','number','textarea'].includes(el.type.toLowerCase())) {
      return failure('INVALID_ARGUMENTS');
    }
    state.changed = true;
    const proto = el.tagName === 'INPUT' ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, request.text);
    el.dispatchEvent(new Event('input', {bubbles: true}));
    el.dispatchEvent(new Event('change', {bubbles: true}));
    return {ok: true, dispatched: true};
  }
  if (request.action === 'click') {
    state.changed = true;
    el.click();
    return {ok: true, dispatched: true};
  }
  return failure('INVALID_ARGUMENTS');
})
