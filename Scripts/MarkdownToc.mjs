// Created by Jobs on 2026年10月18日，星期日.
// Git filters keep Typora's source token local and store a generated disclosure.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync, spawnSync } from 'node:child_process';

export const START = '<!-- jobs-toc:start -->';
export const END = '<!-- jobs-toc:end -->';
const DRIVER = 'jobs-markdown-toc';
const SCRIPT = 'Scripts/MarkdownToc.mjs';
const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const KEYS = ['clean', 'smudge', 'required'].map(key => `filter.${DRIVER}.${key}`);

function linesOf(source) {
  return [...source.matchAll(/[^\n]*(?:\n|$)/g)]
    .filter(match => match[0].length)
    .map(match => ({ text: match[0].replace(/\r?\n$/, ''), start: match.index,
      end: match.index + match[0].replace(/\r?\n$/, '').length }));
}

// Only top-level prose is inspected; examples must never become live TOC markers.
function scan(source) {
  const events = [];
  const lines = linesOf(source);
  let fence = null;
  let comment = false;
  let rawTag = null;
  let frontmatter = false;
  let previous = null;
  for (let index = 0; index < lines.length; index++) {
    let line = lines[index];
    let text = line.text;
    if (index === 0 && text.startsWith('\uFEFF')) {
      text = text.slice(1);
      line = { ...line, start: line.start + 1 };
    }
    if (index === 0 && text === '---') {
      frontmatter = true;
      continue;
    }
    if (frontmatter) {
      if (/^(---|\.\.\.)\s*$/.test(text)) frontmatter = false;
      continue;
    }
    if (rawTag) {
      if (new RegExp(`</${rawTag}\\s*>`, 'i').test(text)) rawTag = null;
      continue;
    }
    const fenced = text.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (fence) {
      if (fenced && fenced[1][0] === fence[0] && fenced[1].length >= fence.length && !fenced[2].trim()) fence = null;
      continue;
    }
    if (fenced && !(fenced[1][0] === '`' && fenced[2].includes('`'))) {
      fence = fenced[1];
      previous = null;
      continue;
    }
    if (/^(?: {4}|\t)/.test(text)) {
      previous = null;
      continue;
    }
    if (!comment && (text === START || text === END || text === '[toc]')) {
      events.push({ ...line, kind: text === START ? 'start' : text === END ? 'end' : 'toc' });
      previous = null;
      continue;
    }
    const raw = text.match(/^ {0,3}<(pre|script|style|textarea)(?:\s|>)/i);
    if (raw && !comment) {
      if (!new RegExp(`</${raw[1]}\\s*>`, 'i').test(text)) rawTag = raw[1];
      previous = null;
      continue;
    }
    // Strip comments before looking for headings, including multi-line comments.
    let visible = '';
    while (text.length) {
      if (comment) {
        const close = text.indexOf('-->');
        if (close < 0) break;
        text = text.slice(close + 3);
        comment = false;
      } else {
        const open = text.indexOf('<!--');
        visible += open < 0 ? text : text.slice(0, open);
        if (open < 0) break;
        text = text.slice(open + 4);
        comment = true;
      }
    }
    const heading = visible.match(/^ {0,3}(#{1,6})(?:[ \t]+(.*)|[ \t]*)$/);
    if (heading) {
      events.push({ ...line, kind: 'heading', level: heading[1].length,
        raw: (heading[2] ?? '').replace(/[ \t]+#+[ \t]*$/, '').trim() });
      previous = null;
    } else if (previous && /^ {0,3}(=+|-+)[ \t]*$/.test(visible)) {
      events.push({ ...previous, kind: 'heading', level: visible.trim()[0] === '=' ? 1 : 2, raw: previous.raw });
      previous = null;
    } else {
      previous = visible.trim() && !/^ {0,3}(?:>|[-+*] |\d+[.)] |<)/.test(visible)
        ? { ...line, raw: visible.trim() } : null;
    }
  }
  return events;
}

function sourceForm(source) {
  const events = scan(source);
  const markers = events.filter(event => event.kind === 'start' || event.kind === 'end');
  if (!markers.length) return source;
  if (markers.length !== 2 || markers[0].kind !== 'start' || markers[1].kind !== 'end') {
    throw new Error('目录标记不完整或重复；请保留成对的 jobs-toc:start / jobs-toc:end。');
  }
  const body = source.slice(markers[0].end, markers[1].start).trim();
  if (!body.startsWith('<details>') || !body.endsWith('</details>')) {
    throw new Error('生成目录块结构异常，已停止转换。');
  }
  return source.slice(0, markers[0].start) + '[toc]' + source.slice(markers[1].end);
}

function decodeEntities(value) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0', copy: '©', reg: '®' };
  return value.replace(/&(#x[\da-f]+|#\d+|[a-z]+);/gi, (all, name) => {
    if (name[0] !== '#') return entities[name.toLowerCase()] ?? all;
    const code = name[1].toLowerCase() === 'x' ? parseInt(name.slice(2), 16) : Number(name.slice(1));
    return code > 0 && code <= 0x10ffff && !(code >= 0xd800 && code <= 0xdfff) ? String.fromCodePoint(code) : '\uFFFD';
  });
}

function inlineText(raw) {
  const protectedText = [];
  const protect = text => `\uE000${protectedText.push(text) - 1}\uE001`;
  return decodeEntities(raw
    .replace(/\\([!"#$%&'()*+,\-./:;<=>?@[\]\\^_`{|}~])/g, (_, text) => protect(text))
    .replace(/(`+)([\s\S]*?)\1/g, (_, ticks, text) => protect(text.replace(/\s+/g, ' ')))
    .replace(/<(https?:\/\/[^<>\s]+)>/g, '$1')
    .replace(/<[^>]*>/g, '')
    .replace(/!?\[([^\]]*)\]\((?:[^()\n]|\([^()]*\))*\)/g, '$1')
    .replace(/!?\[([^\]]*)\]\[[^\]]*\]/g, '$1')
    .replace(/(\*\*|__|~~)(?=\S)([\s\S]*?\S)\1/g, '$2')
    .replace(/(?<![\p{L}\p{N}])([*_])(?=\S)(.*?\S)\1(?![\p{L}\p{N}])/gu, '$2')
    .replace(/\uE000(\d+)\uE001/g, (_, index) => protectedText[Number(index)])).trim();
}

function headingEntries(source) {
  const slugs = new Set();
  const explicitIds = new Set();
  return scan(source).filter(event => event.kind === 'heading').map(heading => {
    const raw = heading.raw.replace(/<a\b[^>]*href=["']#(?:前言|🔚)["'][^>]*>\s*(?:<b>)?\s*[🔼🔽]\s*(?:<\/b>)?\s*<\/a>/gu, '').trim();
    const title = inlineText(raw);
    const base = inlineText(heading.raw).toLowerCase().replace(/[^\p{L}\p{M}\p{N} _-]/gu, '').replace(/ /g, '-');
    let slug = base;
    let suffix = 0;
    while (slugs.has(slug)) slug = `${base}-${++suffix}`;
    slugs.add(slug);
    const id = [...raw.matchAll(/<(span|a|strong|b)\b[^>]*\s(?:id|name)=(?:"([^"]+)"|'([^']+)'|([^\s>]+))[^>]*>([\s\S]*?)<\/\1>/gi)]
      .find(match => inlineText(match[5]).length);
    const target = id ? decodeEntities(id[2] ?? id[3] ?? id[4]) : slug;
    if (id && explicitIds.has(target)) throw new Error(`标题锚点重复：${target}`);
    if (id) explicitIds.add(target);
    if (!title || !target) throw new Error('标题为空或无法生成锚点，请给标题增加唯一的语义 id。');
    return { level: heading.level, title, target };
  }).filter(heading => heading.level >= 2);
}

export function smudgeMarkdown(source) {
  return sourceForm(source);
}

export function cleanMarkdown(source) {
  const local = sourceForm(source);
  const tokens = scan(local).filter(event => event.kind === 'toc');
  if (tokens.length > 1) throw new Error('一份 README 只支持一个独占行的 [toc]。');
  if (!tokens.length) return local;
  const eol = local.includes('\r\n') ? '\r\n' : '\n';
  const entries = headingEntries(local);
  const stack = [];
  const links = entries.map(entry => {
    while (stack.length && stack.at(-1) >= entry.level) stack.pop();
    const indent = '  '.repeat(stack.length);
    stack.push(entry.level);
    const label = entry.title.replace(/([\\[\]`*_<>])/g, '\\$1');
    return `${indent}- [${label}](#${encodeURIComponent(entry.target)})`;
  });
  const block = [START, '<details>', '<summary>📚 目录（点击展开 / 收起）</summary>', '',
    ...(links.length ? links : ['暂无章节。']), '', '</details>', END].join(eol);
  return local.slice(0, tokens[0].start) + block + local.slice(tokens[0].end);
}

export function checkMarkdown(source) {
  return scan(source).some(event => event.kind === 'start') && cleanMarkdown(source) === source;
}

function git(args, options = {}) {
  return execFileSync('git', args, { cwd: ROOT, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'], ...options });
}

function requireRepository() {
  if (fs.realpathSync(git(['rev-parse', '--show-toplevel']).trim()) !== fs.realpathSync(ROOT)) {
    throw new Error('安装器必须位于目标仓库的 Scripts 目录，不能改写父仓配置。');
  }
}

function localValues(key) {
  const result = spawnSync('git', ['config', '--local', '--null', '--get-all', key], { cwd: ROOT, encoding: 'utf8' });
  if (result.status === 1) return [];
  if (result.status !== 0) throw new Error(result.stderr || '无法读取 Git 配置。');
  return result.stdout.split('\0').slice(0, -1);
}

function replaceLocal(key, values) {
  const result = spawnSync('git', ['config', '--local', '--unset-all', key], { cwd: ROOT, encoding: 'utf8' });
  if (result.status !== 0 && result.status !== 5) throw new Error(result.stderr || '无法移除 Git 配置。');
  for (const value of values) git(['config', '--local', '--add', key, value]);
}

function shellQuote(value) {
  return "'" + value.replaceAll("'", "'\\''") + "'";
}

function expectedConfiguration() {
  const node = shellQuote(process.execPath.replaceAll('\\', '/'));
  return { [KEYS[0]]: [`${node} ${shellQuote(SCRIPT)} clean`],
    [KEYS[1]]: [`${node} ${shellQuote(SCRIPT)} smudge`], [KEYS[2]]: ['true'] };
}

function statePath() {
  return path.resolve(ROOT, git(['rev-parse', '--git-path', 'jobs-markdown-toc.json']).trim());
}

function install() {
  requireRepository();
  if (!/^\/README\.md\s+filter=jobs-markdown-toc\s*$/m.test(fs.readFileSync(path.join(ROOT, '.gitattributes'), 'utf8'))) {
    throw new Error('.gitattributes 缺少 /README.md filter=jobs-markdown-toc。');
  }
  const current = Object.fromEntries(KEYS.map(key => [key, localValues(key)]));
  const stateFile = statePath();
  const state = fs.existsSync(stateFile) ? JSON.parse(fs.readFileSync(stateFile, 'utf8')) : null;
  const processFilter = spawnSync('git', ['config', '--get', `filter.${DRIVER}.process`], { cwd: ROOT, encoding: 'utf8' });
  if (processFilter.status !== 1) throw new Error('发现同名 process 过滤器或配置读取失败，停止安装，避免绕过 clean / smudge。');
  const effective = spawnSync('git', ['config', '--get-regexp', `^filter\\.${DRIVER}\\.`], { cwd: ROOT, encoding: 'utf8' });
  if (!state && effective.status !== 1) throw new Error('存在同名过滤器配置或读取失败，保留原配置并停止安装。');
  if (state && (state.version !== 1 || JSON.stringify(current) !== JSON.stringify(state.installed))) {
    throw new Error('过滤器配置已被其他操作改动，保留现场并停止安装。');
  }
  const readme = path.join(ROOT, 'README.md');
  const before = fs.readFileSync(readme, 'utf8');
  const after = smudgeMarkdown(before);
  if (!checkMarkdown(cleanMarkdown(after))) throw new Error('README.md 没有独占行的 [toc]，未安装过滤器。');
  const installed = expectedConfiguration();
  const next = { version: 1, previous: state?.previous ?? current, installed };
  // Keep the recovery record before touching config; only this driver's keys are changed.
  fs.writeFileSync(stateFile, JSON.stringify(next, null, 2) + '\n', { mode: 0o600 });
  try {
    for (const key of KEYS) replaceLocal(key, installed[key]);
    if (after !== before) fs.writeFileSync(readme, after);
  } catch (error) {
    for (const key of KEYS) replaceLocal(key, current[key]);
    if (state) fs.writeFileSync(stateFile, JSON.stringify(state, null, 2) + '\n');
    else fs.unlinkSync(stateFile);
    throw error;
  }
  console.log('已启用本仓 README 过滤器：本地 [toc] → 暂存时生成折叠目录。未暂存、提交或推送。');
}

function uninstall() {
  requireRepository();
  const file = statePath();
  if (!fs.existsSync(file)) throw new Error('没有本工具的安装记录，未修改任何配置。');
  const state = JSON.parse(fs.readFileSync(file, 'utf8'));
  const current = Object.fromEntries(KEYS.map(key => [key, localValues(key)]));
  if (state.version !== 1 || JSON.stringify(current) !== JSON.stringify(state.installed)) {
    throw new Error('过滤器配置已变化，停止卸载，避免覆盖其他操作。');
  }
  const readme = path.join(ROOT, 'README.md');
  const before = fs.readFileSync(readme, 'utf8');
  const generated = cleanMarkdown(before);
  try {
    for (const key of KEYS) replaceLocal(key, state.previous[key]);
    if (generated !== before) fs.writeFileSync(readme, generated);
  } catch (error) {
    for (const key of KEYS) replaceLocal(key, current[key]);
    throw error;
  }
  fs.unlinkSync(file);
  console.log('已恢复本工具安装前的本仓配置，工作区 README 保留折叠目录；后续需自行重新生成。未修改暂存区。');
}

function main(args) {
  const [mode, ...extra] = args;
  if (extra.length) throw new Error('不支持额外参数；使用 help 查看入口。');
  if (mode === 'clean' || mode === 'smudge') {
    const bytes = fs.readFileSync(0);
    const source = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
    process.stdout.write(mode === 'clean' ? cleanMarkdown(source) : smudgeMarkdown(source));
  } else if (mode === 'install') {
    install();
  } else if (mode === 'uninstall') {
    uninstall();
  } else if (mode === 'check') {
    requireRepository();
    if (!checkMarkdown(git(['show', ':README.md']))) {
      throw new Error('暂存区 README 的折叠目录缺失或过期；安装过滤器后整文件重新暂存 README.md。');
    }
    console.log('暂存区 README 目录与其正文一致。');
  } else if (mode === 'status') {
    requireRepository();
    for (const key of KEYS) console.log(`${key} = ${localValues(key).join(', ') || '(未配置)'}`);
    console.log(git(['check-attr', 'filter', '--', 'README.md']).trim());
  } else if (mode === 'preview') {
    process.stdout.write(cleanMarkdown(fs.readFileSync(path.join(ROOT, 'README.md'), 'utf8')));
  } else if (!mode || mode === 'help') {
    console.log('用法：node Scripts/MarkdownToc.mjs install | status | uninstall | check | preview\nclean / smudge 仅供 Git 从标准输入调用；preview 输出发布版 Markdown，不写文件。');
  } else {
    throw new Error(`未知模式：${mode}`);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    console.error(`MarkdownToc：${error.message}`);
    process.exitCode = 1;
  }
}
