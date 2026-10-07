.pragma library

function matches(text, query) {
  const words = query.toLowerCase().trim().split(/\s+/);
  const haystack = text.toLowerCase();
  return words.every(word => haystack.includes(word));
}

function pickerRows(lines, query) {
  return lines.map((text, index) => ({ text: text, index: index }))
    .filter(row => matches(row.text, query));
}

function applicationRows(entries, query) {
  return entries.filter(entry => !entry.noDisplay)
    .filter(entry => matches(
      [entry.name, entry.genericName, ...(entry.keywords || [])].join(" "), query))
    .map(entry => ({
      text: entry.name,
      detail: entry.genericName,
      icon: entry.icon,
      id: entry.id
    }))
    .sort((a, b) => {
      const left = a.text.toLowerCase();
      const right = b.text.toLowerCase();
      if (left !== right)
        return left < right ? -1 : 1;
      return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
    });
}

function navigate(index, delta, count) {
  return count ? Math.max(0, Math.min(count - 1, index + delta)) : -1;
}

function routeQuery(query, picker, appCount) {
  const forced = query.startsWith("=");
  const expression = forced ? query.slice(1) : query;
  const math = !picker && (forced || (appCount === 0 && query.trim() !== ""));
  return { math: math, text: math ? query : "", hasExpression: math && expression.trim() !== "" };
}

function screenForLaunch(screens, name, hyprland) {
  return screens.find(screen => screen.name === name)
    ?? (hyprland ? null : screens[0] ?? null);
}
