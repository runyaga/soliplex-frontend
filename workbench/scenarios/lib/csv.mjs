// RFC 4180 cells, including embedded commas, quotes, CR and LF.
export function parseCsv(text) {
  const rows = [];
  let row = [], cell = '', quoted = false, closed = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (ch === '"') { quoted = false; closed = true; }
      else cell += ch;
    } else if (ch === ',' || ch === '\r' || ch === '\n') {
      row.push(cell); cell = ''; closed = false;
      if (ch !== ',') {
        rows.push(row); row = [];
        if (ch === '\r' && text[i + 1] === '\n') i++;
      }
    } else if (ch === '"' && !cell && !closed) quoted = true;
    else {
      if (closed || ch === '"') throw new Error('Malformed CSV quoting');
      cell += ch;
    }
  }
  if (quoted) throw new Error('Unterminated CSV cell');
  if (cell || row.length || closed) rows.push([...row, cell]);
  if (rows.some(row => row.length !== rows[0].length)) throw new Error('CSV column count mismatch');
  return rows;
}

export function csvCell(value) {
  const text = typeof value === 'object' || typeof value === 'boolean' ? JSON.stringify(value) : String(value);
  return /^[=+\-@\t\r]/.test(text) ? `'${text}` : text;
}
