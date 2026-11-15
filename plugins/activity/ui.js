const KINDS = [
  ['all', 'ทั้งหมด'],
  ['mod', 'ลงโทษ'],
  ['player', 'ผู้เล่น'],
  ['world', 'เซิร์ฟเวอร์'],
  ['code', 'โค้ด'],
  ['report', 'รีพอร์ต'],
  ['plugin', 'ปลั๊กอิน']
];
const KIND_LABEL = Object.fromEntries(KINDS);
const MAX_ROWS = 1000;
const FOLLOW_SLACK = 24;

const pad = (value) => String(value).padStart(2, '0');

function stamp(seconds) {
  const date = new Date(seconds * 1000);
  const time = `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  if (date.toDateString() === new Date().toDateString()) return time;
  return `${pad(date.getDate())}/${pad(date.getMonth() + 1)} ${time}`;
}

export default (ctx) => {
  const { icon, iconButton, emptyState, searchField, segmented, copyToClipboard, toast } = ctx.ui;
  let kind = 'all';
  let words = [];
  let follow = true;

  const $count = $('<span>', { class: 'count tag' });
  const $rows = $('<div>', { class: 'activity-rows' });
  const $empty = emptyState('terminal', 'ยังไม่มีการกระทำของแอดมิน').addClass('activity-empty');
  const $console = $('<div>', { class: 'activity-console scroll' }).append($rows, $empty);
  const $latest = $('<button>', { class: 'activity-latest', hidden: true }).append(icon('arrow-down'), $('<span>', { text: 'ล่าสุด' }));

  const matches = ($row) => (kind === 'all' || $row.attr('data-kind') === kind)
    && words.every((word) => $row.data('search').includes(word));

  function refresh() {
    let visible = 0;
    $rows.children().each((_, element) => {
      const $row = $(element);
      const show = matches($row);
      $row.prop('hidden', !show);
      if (show) visible += 1;
    });
    $count.text(`${visible} รายการ`);
    $empty.prop('hidden', visible > 0);
  }

  const atBottom = () => $console[0].scrollHeight - $console[0].scrollTop - $console[0].clientHeight <= FOLLOW_SLACK;

  function toBottom() {
    $console[0].scrollTop = $console[0].scrollHeight;
    follow = true;
    $latest.prop('hidden', true);
  }

  function row(entry) {
    const $row = $('<div>', { class: 'activity-row', 'data-kind': entry.kind, 'data-id': entry.id }).append(
      $('<span>', { class: 'activity-time', text: stamp(entry.time) }),
      $('<span>', { class: 'activity-kind', text: KIND_LABEL[entry.kind] }),
      $('<span>', { class: 'activity-admin', text: entry.admin }),
      $('<span>', { class: 'activity-text', text: entry.text })
    );
    $row.data('search', `${entry.admin} ${entry.text} ${entry.detail ?? ''}`.toLowerCase());
    if (entry.detail) {
      $row.addClass('expandable').append(
        $('<div>', { class: 'activity-detail', hidden: true }).append(
          $('<pre>', { text: entry.detail }),
          iconButton('copy', 'คัดลอก', (event) => {
            event.stopPropagation();
            copyToClipboard(entry.detail);
            toast('คัดลอกแล้ว', 2000, 'success');
          })
        )
      );
    }
    return $row;
  }

  function trim() {
    const extra = $rows.children().length - MAX_ROWS;
    if (extra > 0) $rows.children().slice(0, extra).remove();
  }

  $rows.on('click', '.activity-row.expandable', (event) => {
    if (window.getSelection().toString() || $(event.target).closest('.activity-detail').length) return;
    const $detail = $(event.currentTarget).find('.activity-detail');
    $detail.prop('hidden', !$detail.prop('hidden'));
  });

  $console.on('scroll', () => {
    follow = atBottom();
    if (follow) $latest.prop('hidden', true);
  });

  $latest.on('click', toBottom);

  ctx.on('history', ({ entries }) => {
    $rows.empty().append(entries.map(row));
    trim();
    refresh();
    toBottom();
  });

  ctx.on('entry', (entry) => {
    const $row = row(entry);
    $rows.append($row);
    trim();
    $row.prop('hidden', !matches($row));
    refresh();
    if (follow) toBottom();
    else if (matches($row)) $latest.prop('hidden', false);
  });

  ctx.page({
    mount($host) {
      $host.addClass('flush activity').append(
        $('<div>', { class: 'bar pill' }).append(
          $('<span>', { class: 'activity-mark' }).append(icon('terminal')),
          $count,
          $('<span>', { class: 'spacer' }),
          segmented(KINDS, kind, (value) => {
            kind = value;
            refresh();
            toBottom();
          }),
          searchField('ค้นหา', (query) => {
            words = query.toLowerCase().split(/\s+/).filter(Boolean);
            refresh();
            toBottom();
          }).addClass('activity-search')
        ),
        $('<div>', { class: 'activity-body' }).append($console, $latest)
      );
      refresh();
      ctx.nui('sync');
    }
  });
};
