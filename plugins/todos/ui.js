const CARD_W = 264;
const ZOOM_MIN = 0.4;
const ZOOM_MAX = 1.5;
const ZOOM_STEP = 0.1;
const FIT_MARGIN = 96;
const DRAG_SLOP = 3;
const COLORS = ['gray', 'red', 'amber', 'green', 'blue', 'violet'];

function ago(seconds) {
  const elapsed = Math.max(0, Math.floor(Date.now() / 1000) - seconds);
  if (elapsed < 60) return 'เมื่อสักครู่';
  if (elapsed < 3600) return `${Math.floor(elapsed / 60)} นาทีที่แล้ว`;
  if (elapsed < 86400) return `${Math.floor(elapsed / 3600)} ชม.ที่แล้ว`;
  return new Date(seconds * 1000).toLocaleDateString('th-TH', { day: 'numeric', month: 'short' });
}

export default (ctx) => {
  const { icon, iconButton, iconTextButton, emptyState, confirmModal } = ctx.ui;
  const cards = new Map();
  const nodes = new Map();
  const stale = new Set();
  let view = { x: 0, y: 0, zoom: 1 };
  let mounted = false;
  let fitted = false;
  let selectedId = null;

  const $count = $('<span>', { class: 'count tag' });
  const $world = $('<div>', { class: 'todos-world' });
  const $zoom = $('<span>', { class: 'count todos-zoom' });
  const $empty = emptyState('list-todo', 'ดับเบิลคลิกพื้นที่ว่างเพื่อเพิ่มโน้ตใบแรก').addClass('todos-empty');
  const $canvas = $('<div>', { class: 'todos-canvas', tabindex: -1 }).append(
    $world,
    $empty,
    $('<p>', { class: 'todos-hint', text: 'ดับเบิลคลิกเพื่อเพิ่มโน้ต ลากพื้นหลังเพื่อเลื่อน หมุนล้อเมาส์เพื่อซูม' }),
    $('<div>', { class: 'todos-tools' }).append(
      iconButton('minus', 'ซูมออก', () => zoomAt(canvasCenter(), view.zoom - ZOOM_STEP)),
      $zoom,
      iconButton('plus', 'ซูมเข้า', () => zoomAt(canvasCenter(), view.zoom + ZOOM_STEP)),
      iconButton('maximize', 'พอดีจอ', fitView)
    )
  );

  function paintView() {
    const { x, y, zoom } = view;
    $world[0].style.transform = `translate(${x}px, ${y}px) scale(${zoom})`;
    $canvas[0].style.backgroundSize = `${24 * zoom}px ${24 * zoom}px`;
    $canvas[0].style.backgroundPosition = `${x}px ${y}px`;
    $zoom.text(`${Math.round(zoom * 100)}%`);
  }

  function toCanvas(event) {
    const rect = $canvas[0].getBoundingClientRect();
    const scale = rect.width / $canvas[0].offsetWidth;
    return { x: (event.clientX - rect.left) / scale, y: (event.clientY - rect.top) / scale };
  }

  function toWorld(point) {
    return { x: (point.x - view.x) / view.zoom, y: (point.y - view.y) / view.zoom };
  }

  const canvasCenter = () => ({ x: $canvas[0].offsetWidth / 2, y: $canvas[0].offsetHeight / 2 });

  function zoomAt(point, requested) {
    const zoom = Math.min(ZOOM_MAX, Math.max(ZOOM_MIN, requested));
    view = {
      x: point.x - ((point.x - view.x) / view.zoom) * zoom,
      y: point.y - ((point.y - view.y) / view.zoom) * zoom,
      zoom
    };
    paintView();
  }

  function fitView() {
    const { offsetWidth, offsetHeight } = $canvas[0];
    const list = [...cards.values()];
    if (list.length === 0) {
      view = { x: offsetWidth / 2, y: offsetHeight / 2, zoom: 1 };
      paintView();
      return;
    }
    const left = Math.min(...list.map((card) => card.x));
    const top = Math.min(...list.map((card) => card.y));
    const right = Math.max(...list.map((card) => card.x + CARD_W));
    const bottom = Math.max(...list.map((card) => card.y + nodes.get(card.id)[0].offsetHeight));
    const zoom = Math.max(ZOOM_MIN, Math.min(1, (offsetWidth - FIT_MARGIN) / (right - left), (offsetHeight - FIT_MARGIN) / (bottom - top)));
    view = {
      x: (offsetWidth - (right - left) * zoom) / 2 - left * zoom,
      y: (offsetHeight - (bottom - top) * zoom) / 2 - top * zoom,
      zoom
    };
    paintView();
  }

  function refreshCount() {
    const list = [...cards.values()];
    const done = list.filter((card) => card.items.length > 0 && card.items.every((item) => item.done)).length;
    $count.text(`${list.length} โน้ต · เสร็จ ${done}`);
    $empty.prop('hidden', list.length > 0);
  }

  function payload(card) {
    const out = { title: card.title, color: card.color, x: Math.round(card.x), y: Math.round(card.y), items: card.items.map(({ text, done }) => ({ text, done })) };
    if (card.id) out.id = card.id;
    return out;
  }

  function edit(id, change, focus) {
    const card = structuredClone(cards.get(id));
    change(card);
    cards.set(id, card);
    draw(card, focus);
    refreshCount();
    ctx.nui('save', payload(card));
  }

  function createAt(point) {
    const world = toWorld(point);
    ctx.nui('save', payload({ title: '', color: 'gray', x: world.x - CARD_W / 2, y: world.y - 24, items: [] }));
  }

  function remove(card) {
    const run = () => ctx.nui('remove', { id: card.id });
    if (!card.title && card.items.length === 0) {
      run();
      return;
    }
    confirmModal({ title: 'ลบโน้ต', description: card.title || `เช็กลิสต์ ${card.items.length} รายการ`, onConfirm: run });
  }

  function select(id) {
    if (selectedId !== null && nodes.has(selectedId)) nodes.get(selectedId).removeClass('selected');
    selectedId = id;
    if (id !== null) nodes.get(id).addClass('selected');
  }

  const editing = (id) => {
    const active = document.activeElement;
    return active?.tagName === 'INPUT' && nodes.get(id)?.[0].contains(active);
  };

  function itemRow(card, item, index) {
    return $('<div>', { class: `todos-item${item.done ? ' done' : ''}` }).append(
      $('<button>', { class: 'todos-check', type: 'button', 'aria-pressed': String(item.done), 'aria-label': item.done ? 'ยกเลิกเสร็จ' : 'ทำเครื่องหมายว่าเสร็จ' })
        .append(icon('check'))
        .on('click', () => edit(card.id, (next) => { next.items[index].done = !item.done; })),
      $('<input>', { class: 'todos-text', value: item.text, maxlength: 200, spellcheck: false })
        .on('keydown', (event) => { if (event.key === 'Enter') event.target.blur(); })
        .on('change', (event) => {
          const text = event.target.value.trim();
          edit(card.id, (next) => {
            if (text) next.items[index].text = text;
            else next.items.splice(index, 1);
          });
        }),
      iconButton('x', 'ลบรายการ', () => edit(card.id, (next) => { next.items.splice(index, 1); }))
    );
  }

  function cardBody(card) {
    const total = card.items.length;
    const doneCount = card.items.filter((item) => item.done).length;
    const $add = $('<input>', { class: 'todos-add', placeholder: '+ เพิ่มรายการ แล้วกด Enter', maxlength: 200, spellcheck: false })
      .on('keydown', (event) => {
        const text = event.target.value.trim();
        if (event.key !== 'Enter' || !text) return;
        edit(card.id, (next) => { next.items.push({ text, done: false }); }, '.todos-add');
      });
    return [
      $('<header>', { class: 'todos-head' }).append(
        $('<button>', { class: 'todos-swatch', type: 'button', 'data-tip': 'เปลี่ยนสี', 'aria-label': 'เปลี่ยนสี' })
          .on('click', () => edit(card.id, (next) => { next.color = COLORS[(COLORS.indexOf(card.color) + 1) % COLORS.length]; })),
        $('<input>', { class: 'todos-title', value: card.title, placeholder: 'ชื่อโน้ต', maxlength: 80, spellcheck: false })
          .on('keydown', (event) => { if (event.key === 'Enter') event.target.blur(); })
          .on('change', (event) => edit(card.id, (next) => { next.title = event.target.value.trim(); })),
        iconButton('trash-2', 'ลบโน้ต', () => remove(card))
      ),
      $('<div>', { class: 'todos-items' }).append(card.items.map((item, index) => itemRow(card, item, index)), $add),
      $('<footer>', { class: 'todos-foot' }).append(
        $('<span>', { class: 'todos-meta', text: `${card.editedBy} · ${ago(card.editedAt)}` }),
        $('<span>', { class: `todos-progress${total > 0 && doneCount === total ? ' todos-done' : ''}`, text: `${doneCount}/${total}` })
      )
    ];
  }

  function place(card) {
    nodes.get(card.id)[0].style.transform = `translate(${card.x}px, ${card.y}px)`;
  }

  function draw(card, focus) {
    let $node = nodes.get(card.id);
    if (!$node) {
      $node = $('<div>', { class: 'todos-card', 'data-id': card.id });
      nodes.set(card.id, $node);
      $world.append($node);
    }
    stale.delete(card.id);
    const complete = card.items.length > 0 && card.items.every((item) => item.done);
    $node.attr('data-color', card.color).toggleClass('todos-done', complete).toggleClass('selected', selectedId === card.id).empty().append(cardBody(card));
    place(card);
    if (focus) $node.find(focus).trigger('focus');
  }

  function receive(card, focus) {
    cards.set(card.id, card);
    if (!mounted) return;
    if (editing(card.id)) stale.add(card.id);
    else draw(card, focus);
    refreshCount();
  }

  function forget(id) {
    cards.delete(id);
    stale.delete(id);
    if (selectedId === id) selectedId = null;
    nodes.get(id)?.remove();
    nodes.delete(id);
    refreshCount();
  }

  ctx.on('board', (data) => {
    const incoming = new Map(Object.values(data.cards).map((card) => [card.id, card]));
    [...cards.keys()].filter((id) => !incoming.has(id)).forEach(forget);
    incoming.forEach((card) => receive(card));
    if (mounted && !fitted) {
      fitted = true;
      fitView();
    }
  });

  ctx.on('card', ({ card, mine }) => {
    receive(card, mine ? '.todos-title' : null);
    if (mine && mounted) select(card.id);
  });

  ctx.on('removed', ({ id }) => forget(id));

  function track(onMove, onUp) {
    const up = (event) => {
      $(document).off('mousemove', onMove).off('mouseup', up);
      onUp(event);
    };
    $(document).on('mousemove', onMove).on('mouseup', up);
  }

  function startPan(event) {
    const origin = toCanvas(event);
    const start = { x: view.x, y: view.y };
    $canvas.addClass('panning');
    track((move) => {
      const point = toCanvas(move);
      view.x = start.x + point.x - origin.x;
      view.y = start.y + point.y - origin.y;
      paintView();
    }, () => $canvas.removeClass('panning'));
  }

  function startDrag(event, id) {
    const card = cards.get(id);
    const origin = toWorld(toCanvas(event));
    const start = { x: card.x, y: card.y };
    let moved = false;
    track((move) => {
      const point = toWorld(toCanvas(move));
      const dx = point.x - origin.x;
      const dy = point.y - origin.y;
      if (!moved && Math.hypot(dx, dy) * view.zoom < DRAG_SLOP) return;
      moved = true;
      $canvas.addClass('dragging');
      card.x = start.x + dx;
      card.y = start.y + dy;
      place(card);
    }, () => {
      $canvas.removeClass('dragging');
      if (moved) edit(id, (next) => { next.x = card.x; next.y = card.y; });
    });
  }

  $canvas.on('mousedown', (event) => {
    if (event.button !== 0) return;
    const $target = $(event.target);
    if ($target.closest('.todos-tools').length) return;
    const $node = $target.closest('.todos-card');
    if (!$node.length) {
      select(null);
      startPan(event);
      return;
    }
    const id = $node.attr('data-id');
    select(id);
    if (!$target.closest('input, button').length) startDrag(event, id);
  });

  $canvas.on('dblclick', (event) => {
    if ($(event.target).closest('.todos-card, .todos-tools').length) return;
    createAt(toCanvas(event));
  });

  $canvas.on('wheel', (event) => {
    const direction = event.originalEvent.deltaY < 0 ? 1 : -1;
    zoomAt(toCanvas(event.originalEvent), view.zoom + direction * ZOOM_STEP);
  });

  $canvas.on('focusout', 'input', (event) => {
    const id = $(event.target).closest('.todos-card').attr('data-id');
    setTimeout(() => {
      if (stale.has(id) && cards.has(id) && !editing(id)) draw(cards.get(id));
    });
  });

  ctx.page({
    mount($host) {
      mounted = true;
      $host.addClass('flush todos').append(
        $('<div>', { class: 'bar pill' }).append(
          $('<span>', { class: 'todos-mark' }).append(icon('list-todo')),
          $count,
          $('<span>', { class: 'spacer' }),
          iconTextButton('plus', 'เพิ่มโน้ต', 'primary', () => createAt(canvasCenter()))
        ),
        $canvas
      );
      cards.forEach((card) => draw(card));
      refreshCount();
      paintView();
      setInterval(() => $world.find('.todos-meta').each((_, element) => {
        const card = cards.get($(element).closest('.todos-card').attr('data-id'));
        element.textContent = `${card.editedBy} · ${ago(card.editedAt)}`;
      }), 60_000);
      ctx.nui('sync');
    }
  });
};
