// Created by Jobs on 2026年10月18日，星期日.
// Filter tests use disposable repositories so the real index and config stay untouched.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { checkMarkdown, cleanMarkdown, smudgeMarkdown } from '../Scripts/MarkdownToc.mjs';

const scriptPath = fileURLToPath(new URL('../Scripts/MarkdownToc.mjs', import.meta.url));
const start = '<!-- jobs-toc:start -->';
const end = '<!-- jobs-toc:end -->';

function tocOf(source) {
  const generated = cleanMarkdown(source);
  const offset = generated.search(/<!-- jobs-toc:start -->\r?\n<details>/);
  assert.notEqual(offset, -1, 'Expected a generated disclosure');
  return generated.slice(offset, generated.indexOf(end, offset) + end.length);
}

function hasTarget(toc, target) {
  assert.ok(toc.includes(`](#${encodeURIComponent(target)})`), `Missing target: ${target}\n${toc}`);
}

function temporaryRepository(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "Markdown TOC '实验 "));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const globalConfig = path.join(root, 'global.gitconfig');
  fs.writeFileSync(globalConfig, '[user]\n\tname = TOC test\n');
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    !/^GIT_(?:DIR|WORK_TREE|INDEX_FILE|CONFIG_PARAMETERS|CONFIG_COUNT|CONFIG_KEY_\d+|CONFIG_VALUE_\d+)$/.test(key)));
  env.GIT_CONFIG_NOSYSTEM = '1';
  env.GIT_CONFIG_GLOBAL = globalConfig;
  env.GIT_TERMINAL_PROMPT = '0';
  const run = (command, args, options = {}) => {
    const result = spawnSync(command, args, { cwd: root, env, encoding: 'utf8', ...options });
    if (result.error) throw result.error;
    return result;
  };
  const git = (...args) => {
    const result = run('git', args);
    assert.equal(result.status, 0, `git ${args.join(' ')}\n${result.stderr}`);
    return result.stdout;
  };
  const cli = mode => run(process.execPath, ['Scripts/MarkdownToc.mjs', mode]);
  git('init', '--quiet');
  git('config', '--local', 'core.autocrlf', 'false');
  fs.mkdirSync(path.join(root, 'Scripts'));
  fs.copyFileSync(scriptPath, path.join(root, 'Scripts/MarkdownToc.mjs'));
  fs.writeFileSync(path.join(root, '.gitattributes'), '/README.md filter=jobs-markdown-toc\n');
  return { root, globalConfig, run, git, cli };
}

test('clean is idempotent; smudge restores the complete original source', () => {
  const source = '# Project\n\n[toc]\n\n## Install\n\nText stays here.\n\n### Options\n';
  const generated = cleanMarkdown(source);
  assert.ok(generated.includes(`${start}\n<details>\n<summary>`));
  assert.ok(generated.includes(`</details>\n${end}`));
  assert.equal(cleanMarkdown(generated), generated);
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(smudgeMarkdown(source), source);
  assert.equal(checkMarkdown(generated), true);
  assert.equal(checkMarkdown(source), false);
  hasTarget(generated, 'install');
  hasTarget(generated, 'options');
});

test('documents without an active TOC are returned byte for byte', () => {
  const source = '# Demo\n\nInline [toc] is text.\n\n## Section\n';
  assert.equal(cleanMarkdown(source), source);
  assert.equal(smudgeMarkdown(source), source);
  assert.equal(checkMarkdown(source), false);
});

test('existing generated TOC updates after headings are added, renamed, or removed', () => {
  const original = cleanMarkdown('[toc]\n\n## Old name\n\n### Remove me\n');
  const changed = original.replace('## Old name', '## New name').replace('### Remove me', '### New child\n\n## Added');
  assert.equal(checkMarkdown(changed), false);
  const refreshed = cleanMarkdown(changed);
  const toc = tocOf(refreshed);
  hasTarget(toc, 'new-name');
  hasTarget(toc, 'new-child');
  hasTarget(toc, 'added');
  assert.ok(!toc.includes('Old name'));
  assert.ok(!toc.includes('Remove me'));
  assert.equal(checkMarkdown(refreshed), true);
  assert.equal(smudgeMarkdown(refreshed), '[toc]\n\n## New name\n\n### New child\n\n## Added\n');
});

test('Chinese headings, repeated headings, and skipped levels get working targets', () => {
  const toc = tocOf('# Title\n\n[toc]\n\n## 中文标题\n### Same\n#### Same\n###### Deep\n## Same\n');
  hasTarget(toc, '中文标题');
  hasTarget(toc, 'same');
  hasTarget(toc, 'same-1');
  hasTarget(toc, 'same-2');
  hasTarget(toc, 'deep');
  assert.ok(!toc.includes('](#title)'));
  assert.match(toc, /^  - \[Same\]/m);
  assert.match(toc, /^    - \[Same\]/m);
});

test('H1 participates in duplicate slug numbering but is omitted from the TOC', () => {
  const toc = tocOf('[toc]\n\n# Same\n## Same\n');
  hasTarget(toc, 'same-1');
  assert.equal((toc.match(/\[Same\]/g) ?? []).length, 1);
});

test('ordinary underscores inside identifiers remain part of the label and slug', () => {
  const toc = tocOf('[toc]\n\n## API_v2\n\n### `build_step`\n\n## A\tB\n');
  hasTarget(toc, 'api_v2');
  hasTarget(toc, 'build_step');
  hasTarget(toc, 'ab');
  assert.ok(toc.includes('[API\\_v2]'));
});

test('only H2 through H6 and single-line Setext headings are included', () => {
  const toc = tocOf('[toc]\n\nH1 title\n========\n\nSetext section\n--------------\n\n## H2 ##\n### H3\n#### H4\n##### H5\n###### H6\n####### Not a heading\n');
  for (const target of ['setext-section', 'h2', 'h3', 'h4', 'h5', 'h6']) hasTarget(toc, target);
  assert.ok(!toc.includes('H1 title'));
  assert.ok(!toc.includes('Not a heading'));
});

test('code examples, comments, frontmatter, and raw HTML do not create headings or TOCs', () => {
  const source = [
    '---', 'title: Test', '[toc]', '## YAML fake', '---', '',
    '<!--', '[toc]', '## Comment fake', '-->', '',
    '```markdown', '[toc]', '## Fence fake', start, end, '```', '',
    '~~~~', '[toc]', '## Tilde fake', '~~~~', '',
    '    [toc]', '    ## Indented fake', '\t## Tab fake', '',
    '<pre>', '[toc]', '## Pre fake', '</pre>', '',
    '<script>', '[toc]', '## Script fake', '</script>', '',
    '<style>', '[toc]', '## Style fake', '</style>', '',
    '<textarea>', '[toc]', '## Textarea fake', '</textarea>', '',
    '[toc]', '', '## Real section', '',
  ].join('\n');
  const toc = tocOf(source);
  hasTarget(toc, 'real-section');
  assert.ok(!toc.includes('fake'));
  assert.equal(smudgeMarkdown(cleanMarkdown(source)), source);
});

test('inline formatting is converted to safe plain labels and explicit IDs win', () => {
  const source = '[toc]\n\n## <span id="install">**Install** [the tool](https://example.com) `now`</span> <a href="#前言"><b>🔼</b></a> <a href="#🔚"><b>🔽</b></a>\n\n## <strong id="中文 &amp; id">中文说明</strong>\n';
  const toc = tocOf(source);
  hasTarget(toc, 'install');
  hasTarget(toc, '中文 & id');
  assert.ok(toc.includes('[Install the tool now]'));
  assert.ok(!toc.includes('🔼'));
  assert.ok(!toc.includes('🔽'));
  assert.ok(!toc.includes('<span'));
  assert.ok(!toc.includes('https://example.com'));
});

test('empty HTML anchors do not replace the heading slug', () => {
  const toc = tocOf('[toc]\n\n## <a id="empty-anchor"></a>Actual heading\n');
  hasTarget(toc, 'actual-heading');
  assert.ok(!toc.includes('](#empty-anchor)'));
});

test('unrelated disclosure blocks survive both transformations', () => {
  const disclosure = '<details>\n<summary>Extra notes</summary>\n\nKeep these notes.\n\n</details>';
  const source = `[toc]\n\n## Section\n\n${disclosure}\n`;
  assert.equal(smudgeMarkdown(disclosure), disclosure);
  assert.ok(cleanMarkdown(source).includes(disclosure));
  assert.equal(smudgeMarkdown(cleanMarkdown(source)), source);
});

test('BOM, CRLF, trailing newlines, and a first-line TOC are preserved', () => {
  for (const bom of ['', '\uFEFF']) {
    for (const eol of ['\n', '\r\n']) {
      for (const trailing of ['', eol]) {
        const source = `${bom}[toc]${eol}${eol}## 章节${trailing}`;
        const generated = cleanMarkdown(source);
        assert.equal(generated.startsWith('\uFEFF'), Boolean(bom));
        if (eol === '\r\n') assert.ok(!/(?<!\r)\n/.test(generated));
        assert.equal(smudgeMarkdown(generated), source);
        assert.equal(cleanMarkdown(generated), generated);
      }
    }
  }
});

test('duplicate live TOCs and damaged generated markers stop conversion', () => {
  const broken = [
    '[toc]\n\n[toc]\n\n## A\n',
    `${start}\n<details>\n</details>\n`,
    `${end}\n`,
    `${end}\n${start}\n`,
    `${start}\n<details>\n</details>\n${end}\n${end}\n`,
    `${start}\nNot a disclosure\n${end}\n`,
    `${start}\n<details>\n</details>\n${end}\n\n[toc]\n\n## A\n`,
  ];
  for (const source of broken) assert.throws(() => cleanMarkdown(source), undefined, source);
  assert.throws(() => smudgeMarkdown(`${start}\n`));
});

test('Git stages generated content while worktree and checkout retain the Typora token', t => {
  const repo = temporaryRepository(t);
  const readme = path.join(repo.root, 'README.md');
  const source = '# Filter demo\n\n[toc]\n\n## Install\n\n### Options\n';
  fs.writeFileSync(readme, source);
  repo.git('add', 'README.md');
  const initialIndex = repo.git('show', ':README.md');
  const originalGlobal = fs.readFileSync(repo.globalConfig, 'utf8');
  const installed = repo.cli('install');
  assert.equal(installed.status, 0, installed.stderr);
  assert.equal(repo.git('show', ':README.md'), initialIndex, 'install must not stage anything');
  assert.equal(fs.readFileSync(repo.globalConfig, 'utf8'), originalGlobal);
  assert.equal(repo.git('config', '--local', '--get', 'filter.jobs-markdown-toc.required').trim(), 'true');
  assert.equal(repo.cli('install').status, 0, 'install is repeatable');
  assert.equal(repo.cli('status').status, 0);

  repo.git('add', 'README.md');
  const staged = repo.git('show', ':README.md');
  assert.equal(staged, cleanMarkdown(source));
  assert.equal(fs.readFileSync(readme, 'utf8'), source);
  assert.equal(repo.cli('check').status, 0);

  const changed = source.replace('## Install', '## Updated').replace('### Options', '### Added child');
  fs.writeFileSync(readme, changed);
  assert.equal(repo.cli('check').status, 0, 'check reads staged content, not an unstaged worktree');
  repo.git('add', 'README.md');
  const updated = repo.git('show', ':README.md');
  assert.equal(updated, cleanMarkdown(changed));
  assert.ok(!tocOf(updated).includes('Install'));
  assert.equal(repo.cli('check').status, 0);

  const checkout = path.join(repo.root, 'isolated checkout');
  fs.mkdirSync(checkout);
  repo.git('checkout-index', `--prefix=${checkout}${path.sep}`, 'README.md');
  assert.equal(fs.readFileSync(path.join(checkout, 'README.md'), 'utf8'), changed);

  const indexBeforeUninstall = repo.git('show', ':README.md');
  const removed = repo.cli('uninstall');
  assert.equal(removed.status, 0, removed.stderr);
  assert.equal(repo.git('show', ':README.md'), indexBeforeUninstall);
  assert.equal(fs.readFileSync(readme, 'utf8'), cleanMarkdown(changed));
  assert.equal(repo.run('git', ['config', '--local', '--get', 'filter.jobs-markdown-toc.clean']).status, 1);
  assert.equal(fs.readFileSync(repo.globalConfig, 'utf8'), originalGlobal);
});

test('index check rejects stale generated content even when worktree content is correct', t => {
  const repo = temporaryRepository(t);
  const source = '[toc]\n\n## Original\n';
  fs.writeFileSync(path.join(repo.root, 'README.md'), source);
  assert.equal(repo.cli('install').status, 0);
  repo.git('add', 'README.md');
  const stale = cleanMarkdown(source).replace('## Original', '## Changed');
  const object = repo.run('git', ['hash-object', '-w', '--stdin'], { input: stale });
  assert.equal(object.status, 0, object.stderr);
  repo.git('update-index', '--cacheinfo', '100644', object.stdout.trim(), 'README.md');
  const checked = repo.cli('check');
  assert.notEqual(checked.status, 0);
  assert.ok(checked.stderr.length > 0);
});

test('partial staging can make a stale TOC and index check catches either separated hunk', t => {
  const repo = temporaryRepository(t);
  const readme = path.join(repo.root, 'README.md');
  const padding = Array.from({ length: 24 }, (_, index) => `Paragraph ${index + 1}.`).join('\n\n');
  const source = `# Partial staging\n\n[toc]\n\n${padding}\n\n## Original\n\n${padding}\n`;
  fs.writeFileSync(readme, source);
  assert.equal(repo.cli('install').status, 0);
  repo.git('add', 'README.md');
  const originalObject = repo.git('rev-parse', ':README.md').trim();
  const changed = `${source.replace('## Original', '## Changed')}\nUNSTAGED_PARAGRAPH\n`;
  fs.writeFileSync(readme, changed);
  const diff = repo.git('diff', '--no-ext-diff', '--', 'README.md');
  const offsets = [...diff.matchAll(/^@@ /gm)].map(match => match.index);
  assert.ok(offsets.length >= 3, 'TOC, heading, and appended paragraph must have separate hunks');
  const header = diff.slice(0, offsets[0]);
  const hunks = offsets.map((offset, index) => diff.slice(offset, offsets[index + 1] ?? diff.length));
  const tocHunk = hunks.find(hunk => hunk.includes('](#original)'));
  const headingHunk = hunks.find(hunk => hunk.includes('\n-## Original\n'));
  assert.ok(tocHunk && headingHunk && tocHunk !== headingHunk);

  for (const hunk of [tocHunk, headingHunk]) {
    repo.git('update-index', '--cacheinfo', '100644', originalObject, 'README.md');
    const applied = repo.run('git', ['apply', '--cached'], { input: header + hunk });
    assert.equal(applied.status, 0, applied.stderr);
    const partialIndex = repo.git('show', ':README.md');
    assert.notEqual(repo.cli('check').status, 0, 'Partial staging must be reported as stale');
    assert.ok(!partialIndex.includes('UNSTAGED_PARAGRAPH'));

    // Filters must transform the exact blob Git sends rather than reread the worktree.
    const filtered = repo.run(process.execPath, ['Scripts/MarkdownToc.mjs', 'clean'], { input: partialIndex });
    assert.equal(filtered.status, 0, filtered.stderr);
    assert.equal(filtered.stdout, cleanMarkdown(partialIndex));
    assert.ok(!filtered.stdout.includes('UNSTAGED_PARAGRAPH'));
  }

  repo.git('add', 'README.md');
  assert.equal(repo.cli('check').status, 0);
  assert.equal(repo.git('show', ':README.md'), cleanMarkdown(changed));
  assert.equal(fs.readFileSync(readme, 'utf8'), changed);
});

test('install preserves a pre-existing filter configuration and rejects a conflicting owner', t => {
  const repo = temporaryRepository(t);
  fs.writeFileSync(path.join(repo.root, 'README.md'), '[toc]\n\n## A\n');
  repo.git('config', '--local', 'filter.jobs-markdown-toc.clean', 'an-existing-filter');
  const before = repo.git('config', '--local', '--list');
  assert.notEqual(repo.cli('install').status, 0);
  assert.equal(repo.git('config', '--local', '--list'), before);
});

for (const scope of ['local', 'global']) {
  test(`install rejects a pre-existing ${scope} process filter without changing config`, t => {
    const repo = temporaryRepository(t);
    fs.writeFileSync(path.join(repo.root, 'README.md'), '[toc]\n\n## A\n');
    repo.git('config', `--${scope}`, 'filter.jobs-markdown-toc.process', 'an-existing-process-filter');
    const localBefore = repo.git('config', '--local', '--list');
    const globalBefore = fs.readFileSync(repo.globalConfig, 'utf8');
    assert.notEqual(repo.cli('install').status, 0);
    assert.equal(repo.git('config', '--local', '--list'), localBefore);
    assert.equal(fs.readFileSync(repo.globalConfig, 'utf8'), globalBefore);
  });
}
