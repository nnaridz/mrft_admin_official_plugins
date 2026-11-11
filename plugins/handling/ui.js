const AXES = ['x', 'y', 'z'];

const same = (a, b) => (typeof a === 'object' ? AXES.every((axis) => a[axis] === b[axis]) : a === b);
const show = (value) => (typeof value === 'object' ? AXES.map((axis) => value[axis]).join(', ') : String(value));

function xml(groups, values) {
  return groups.flatMap((group) => group.fields).map(({ name, type }) => {
    const value = values[name];
    if (type === 'vector') return `<${name} x="${value.x}" y="${value.y}" z="${value.z}" />`;
    return `<${name} value="${value}" />`;
  }).join('\n');
}

export default (ctx) => {
  const { icon, iconButton, iconTextButton, searchField, emptyState, textField, toast, copyToClipboard, confirmModal } = ctx.ui;
  let groups = [];
  let current = { vehicle: false };
  let query = '';
  const rows = new Map();

  const $name = $('<span>', { class: 'handling-name' });
  const $plate = $('<span>', { class: 'count tag' });
  const $changed = $('<span>', { class: 'count' });
  const $empty = emptyState('car-front', 'ขึ้นรถก่อน แล้วค่า handling ของคันนั้นจะแสดงที่นี่');
  const $fields = $('<div>', { class: 'handling-groups' });
  const $body = $('<div>', { class: 'handling-body scroll' }).append($empty, $fields);
  const $reset = iconTextButton('rotate-ccw', 'คืนค่าเดิม', '', () => confirmModal({
    title: 'คืนค่า handling เดิม',
    description: 'ทุกค่าของรถคันนี้จะกลับเป็นค่าตอนที่ขึ้นรถ',
    onConfirm: () => ctx.nui('reset').then(render)
  }));
  const $copy = iconTextButton('copy', 'คัดลอก XML', 'primary', () => {
    copyToClipboard(xml(groups, current.values));
    toast('คัดลอก handling แล้ว', 3000, 'success');
  });

  function commit(field, $inputs) {
    const texts = $inputs.map((_, input) => input.value.trim()).get();
    const parts = texts.map(Number);
    const valid = texts.every((text) => text !== '') && parts.every(Number.isFinite) && (field.type !== 'integer' || Number.isInteger(parts[0]));
    if (!valid) {
      toast(field.type === 'integer' ? `${field.name} ต้องเป็นจำนวนเต็ม` : `${field.name} ต้องเป็นตัวเลข`, 3000, 'error');
      render(current);
      return;
    }
    const value = field.type === 'vector' ? { x: parts[0], y: parts[1], z: parts[2] } : parts[0];
    ctx.nui('set', { name: field.name, value }).then(render);
  }

  function buildRow(field) {
    const count = field.type === 'vector' ? 3 : 1;
    const $inputs = $(Array.from({ length: count }, (_, i) => textField('', field.type === 'vector' ? AXES[i] : '')
      .addClass('handling-input')
      .attr('inputmode', 'decimal')
      .on('change', () => commit(field, $inputs))
      .on('keydown', (event) => { if (event.key === 'Enter') event.target.blur(); })[0]));
    const $revert = iconButton('undo-2', 'คืนค่านี้', () => ctx.nui('set', { name: field.name, value: current.originals[field.name] }).then(render));
    const $row = $('<div>', { class: 'handling-row' }).append(
      $('<span>', { class: 'handling-dot' }),
      $('<span>', { class: 'handling-field', text: field.name }),
      $revert,
      $('<div>', { class: 'handling-inputs' }).append($inputs)
    );
    rows.set(field.name, { field, $row, $inputs, $revert });
    return $row;
  }

  function build() {
    $fields.empty().append(groups.map((group) => $('<section>', { class: 'handling-group' }).append(
      $('<span>', { class: 'label', text: group.label }),
      group.fields.map(buildRow)
    )));
  }

  function filter() {
    const needle = query.trim().toLowerCase();
    $fields.children().each((_, section) => {
      let visible = 0;
      $(section).find('.handling-row').each((__, row) => {
        const match = row.querySelector('.handling-field').textContent.toLowerCase().includes(needle);
        row.hidden = !match;
        if (match) visible += 1;
      });
      section.hidden = visible === 0;
    });
  }

  function render(state) {
    current = state;
    const vehicle = state.vehicle;
    $empty.prop('hidden', Boolean(vehicle));
    $fields.prop('hidden', !vehicle);
    $reset.prop('disabled', !vehicle);
    $copy.prop('disabled', !vehicle);
    $name.text(vehicle ? vehicle.label : 'ไม่ได้อยู่บนรถ');
    $plate.text(vehicle ? vehicle.plate : '');
    if (!vehicle) {
      $changed.text('');
      return;
    }
    let changed = 0;
    for (const { field, $row, $inputs, $revert } of rows.values()) {
      const value = state.values[field.name];
      const original = state.originals[field.name];
      const isChanged = !same(value, original);
      if (isChanged) changed += 1;
      $row.toggleClass('changed', isChanged);
      $revert.attr('data-tip', `คืนเป็น ${show(original)}`).css('visibility', isChanged ? 'visible' : 'hidden');
      $inputs.each((i, input) => { input.value = field.type === 'vector' ? value[AXES[i]] : value; });
    }
    $changed.text(changed ? `แก้ไขแล้ว ${changed} ค่า` : '');
  }

  ctx.on('state', (state) => {
    if (groups.length) render(state);
  });

  ctx.page({
    mount($host) {
      $host.addClass('flush handling').append(
        $('<div>', { class: 'bar pill' }).append(
          $('<span>', { class: 'handling-mark' }).append(icon('car-front')),
          $name, $plate, $changed,
          searchField('ค้นหาค่า เช่น traction', (value) => { query = value; filter(); }),
          $reset, $copy
        ),
        $body
      );
      ctx.nui('load').then((data) => {
        groups = data.groups;
        build();
        render(data.state);
      });
    }
  });
};
