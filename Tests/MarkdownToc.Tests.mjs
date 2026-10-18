// Created by Jobs on 2026年10月18日，星期日.
// Filter tests use disposable repositories so the real index and config stay untouched.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { checkMarkdown, cleanMarkdown, inspectMarkdown, smudgeMarkdown } from '../Scripts/MarkdownToc.mjs';

const scriptPath = fileURLToPath(new URL('../Scripts/MarkdownToc.mjs', import.meta.url));
const start = '<!-- jobs-toc:start -->';
const end = '<!-- jobs-toc:end -->';

function tocOf(source) {
  const generated = cleanMarkdown(source);
  const offset = generated.search(/<!-- jobs-toc:start -->\r?\n(?:<!-- jobs-toc:source .+ -->\r?\n)?<details>/);
  assert.notEqual(offset, -1, 'Expected a generated disclosure');
  return generated.slice(offset, generated.indexOf(end, offset) + end.length);
}

function hasTarget(toc, target) {
  assert.ok(toc.includes(`](#${encodeURIComponent(target)})`), `Missing target: ${target}\n${toc}`);
}

function linkedAnchorsExist(generated) {
  for (const match of generated.matchAll(/\]\(#([^\n)]+)\)/g)) {
    const target = decodeURIComponent(match[1]);
    assert.ok(generated.includes(`id="${target}"`) || generated.includes(`id='${target}'`),
      `No matching HTML id for #${target}`);
  }
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
  assert.ok(generated.includes(`${start}\n<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->\n<details>\n<summary>`));
  assert.ok(generated.includes(`</details>\n${end}`));
  assert.equal(cleanMarkdown(generated), generated);
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(smudgeMarkdown(source), source);
  assert.equal(checkMarkdown(generated), true);
  assert.equal(checkMarkdown(source), false);
  hasTarget(generated, 'jobs-toc-heading-1');
  hasTarget(generated, 'jobs-toc-heading-2');
  linkedAnchorsExist(generated);
});

test('documents without an active TOC are returned byte for byte', () => {
  const source = '# Demo\n\nInline [toc] is text.\n\n## Section\n';
  assert.equal(cleanMarkdown(source), source);
  assert.equal(smudgeMarkdown(source), source);
  assert.equal(checkMarkdown(source), false);
  assert.deepEqual(inspectMarkdown(source), { tocCount: 0, headingCount: 1 });
});

test('existing generated TOC updates after headings are added, renamed, or removed', () => {
  const original = cleanMarkdown('[toc]\n\n## Old name\n\n### Remove me\n');
  const stale = original.replace('>Old name</span>', '>New name</span>');
  assert.equal(checkMarkdown(stale), false);
  const changed = smudgeMarkdown(original).replace('## Old name', '## New name').replace('### Remove me', '### New child\n\n## Added');
  const refreshed = cleanMarkdown(changed);
  const toc = tocOf(refreshed);
  for (let index = 1; index <= 3; index++) hasTarget(toc, `jobs-toc-heading-${index}`);
  for (const label of ['New name', 'New child', 'Added']) assert.ok(toc.includes(`[${label}]`));
  assert.ok(!toc.includes('Old name'));
  assert.ok(!toc.includes('Remove me'));
  assert.equal(checkMarkdown(refreshed), true);
  linkedAnchorsExist(refreshed);
  assert.equal(smudgeMarkdown(refreshed), '[toc]\n\n## New name\n\n### New child\n\n## Added\n');
});

test('Chinese headings, repeated headings, and skipped levels get working targets', () => {
  const generated = cleanMarkdown('# Title\n\n[toc]\n\n## 中文标题\n### Same\n#### Same\n###### Deep\n## Same\n');
  const toc = tocOf(generated);
  for (let index = 1; index <= 5; index++) hasTarget(toc, `jobs-toc-heading-${index}`);
  assert.ok(!toc.includes('](#title)'));
  assert.match(toc, /^  - \[Same\]/m);
  assert.match(toc, /^    - \[Same\]/m);
  linkedAnchorsExist(generated);
});

test('H1 is unchanged and omitted from the TOC even when H2 repeats its text', () => {
  const generated = cleanMarkdown('[toc]\n\n# Same\n## Same\n');
  const toc = tocOf(generated);
  hasTarget(toc, 'jobs-toc-heading-1');
  assert.equal((toc.match(/\[Same\]/g) ?? []).length, 1);
  assert.ok(generated.includes('\n# Same\n'));
  linkedAnchorsExist(generated);
});

test('ordinary underscores, inline code, and tabs keep their displayed text', () => {
  const toc = tocOf('[toc]\n\n## API_v2\n\n### `build_step`\n\n## A\tB\n');
  for (let index = 1; index <= 3; index++) hasTarget(toc, `jobs-toc-heading-${index}`);
  assert.ok(toc.includes('[API\\_v2]'));
  assert.ok(toc.includes('[build\\_step]'));
  assert.ok(toc.includes('[A\tB]'));
});

test('only H2 through H6 and single-line Setext headings are included with exact roundtrip', () => {
  const source = '[toc]\n\nH1 title\n========\n\nSetext section\n--------------\n\n## H2 ##\n### H3\n#### H4\n##### H5\n###### H6\n####### Not a heading\n';
  const generated = cleanMarkdown(source);
  const toc = tocOf(generated);
  for (let index = 1; index <= 6; index++) hasTarget(toc, `jobs-toc-heading-${index}`);
  assert.ok(!toc.includes('H1 title'));
  assert.ok(!toc.includes('Not a heading'));
  assert.ok(generated.includes('</span><!-- jobs-toc:heading-end --> ##\n'));
  assert.ok(generated.includes('</span><!-- jobs-toc:heading-end -->\n--------------'));
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(cleanMarkdown(generated), generated);
  linkedAnchorsExist(generated);
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
  hasTarget(toc, 'jobs-toc-heading-1');
  assert.ok(!toc.includes('fake'));
  const generated = cleanMarkdown(source);
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(generated.slice(0, generated.indexOf('<!-- jobs-toc:source {"v":2')), source.slice(0, source.lastIndexOf('[toc]')) + `${start}\n`);
  assert.deepEqual(inspectMarkdown(source), { tocCount: 1, headingCount: 1 });
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

test('empty HTML anchors use an automatically generated target', () => {
  const toc = tocOf('[toc]\n\n## <a id="empty-anchor"></a>Actual heading\n');
  hasTarget(toc, 'jobs-toc-heading-1');
  assert.ok(!toc.includes('](#empty-anchor)'));
});

test('font IDs, duplicate IDs, and nested inline spans get reliable targets and exact roundtrip', () => {
  const source = [
    '[toc]', '',
    '## <font id="font-id"><span>Font <b>nested</b></span></font>', '',
    '## <span id="duplicate">First</span>', '',
    '### <b id="duplicate">Second</b>', '',
    '## <span id="unique"><span>Unique nested</span> title</span>', '',
    '## <a id="named-anchor">Named anchor</a>', '',
    '## <strong id="strong-anchor">Strong title</strong>', '',
  ].join('\n');
  const generated = cleanMarkdown(source);
  const toc = tocOf(generated);
  for (let index = 1; index <= 3; index++) hasTarget(toc, `jobs-toc-heading-${index}`);
  for (const id of ['unique', 'named-anchor', 'strong-anchor']) hasTarget(toc, id);
  assert.ok(!toc.includes('](#font-id)'));
  assert.ok(!toc.includes('](#duplicate)'));
  assert.ok(generated.includes('<span id="jobs-toc-heading-1" data-jobs-toc="v2"><font id="font-id">'));
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(cleanMarkdown(generated), generated);
  linkedAnchorsExist(generated);
});

test('explicit IDs duplicated by H1 or prose use owned heading anchors instead', () => {
  const source = [
    '# <span id="intro">Project title</span>', '', '[toc]', '',
    '## <span id="intro">Introduction</span>', '',
    '<a id="prose-id">Existing prose anchor</a>', '',
    '## <strong id="prose-id">Another section</strong>', '',
  ].join('\n');
  const generated = cleanMarkdown(source);
  const toc = tocOf(generated);
  hasTarget(toc, 'jobs-toc-heading-1');
  hasTarget(toc, 'jobs-toc-heading-2');
  assert.ok(!toc.includes('](#intro)'));
  assert.ok(!toc.includes('](#prose-id)'));
  assert.ok(generated.includes('# <span id="intro">Project title</span>\n'));
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(cleanMarkdown(generated), generated);
  linkedAnchorsExist(generated);
});

test('multiple case-insensitive TOCs preserve their original indentation and trailing spaces', () => {
  const source = '\uFEFF  [TOC]  \r\n\r\n## 第一节 ##\r\n\r\n[toc]\t\r\n\r\n### Child\r\n\r\n   [ToC]\r\n';
  const generated = cleanMarkdown(source);
  assert.equal((generated.match(/<!-- jobs-toc:source /g) ?? []).length, 3);
  assert.equal((generated.match(/<details>/g) ?? []).length, 3);
  assert.equal((generated.match(/\]\(#jobs-toc-heading-1\)/g) ?? []).length, 3);
  assert.equal(smudgeMarkdown(generated), source);
  assert.equal(cleanMarkdown(generated), generated);
  assert.deepEqual(inspectMarkdown(source), { tocCount: 3, headingCount: 2 });
  assert.deepEqual(inspectMarkdown(generated), { tocCount: 3, headingCount: 2 });
  linkedAnchorsExist(generated);
});

test('nested link brackets keep CDN and GitHub labels without leaking their URLs', () => {
  const source = '[toc]\n\n## [CDN[-]](https://cdn.example.com/a(b)) 与 [Github[+]](https://github.example.com/repo)\n\n### [outer [inner]](https://example.com/outer)\n';
  const generated = cleanMarkdown(source);
  const toc = tocOf(generated);
  assert.ok(toc.includes('[CDN\\[-\\] 与 Github\\[+\\]]'));
  assert.ok(toc.includes('[outer \\[inner\\]]'));
  assert.ok(!toc.includes('https://'));
  assert.equal(smudgeMarkdown(generated), source);
  linkedAnchorsExist(generated);
});

test('damaged owned heading anchors are rejected instead of silently editing the source', () => {
  const generated = cleanMarkdown('[toc]\n\n## Section\n');
  const missingClose = generated.replace('</span><!-- jobs-toc:heading-end -->', '');
  const missingOpen = generated.replace('<span id="jobs-toc-heading-1" data-jobs-toc="v2">', '');
  assert.throws(() => smudgeMarkdown(missingClose));
  assert.throws(() => cleanMarkdown(missingOpen));
});

test('legacy generated blocks migrate to v2 while unrelated source remains intact', () => {
  const legacy = `${start}\n<details>\n<summary>Old TOC</summary>\n\n- [Section](#section)\n\n</details>\n${end}\n\n## Section\n`;
  const local = '[toc]\n\n## Section\n';
  assert.equal(smudgeMarkdown(legacy), local);
  const generated = cleanMarkdown(legacy);
  assert.ok(generated.includes('jobs-toc:source {"v":2'));
  assert.equal(smudgeMarkdown(generated), local);
  assert.equal(checkMarkdown(generated), true);
  linkedAnchorsExist(generated);
});

test('clean and smudge CLI reject malformed UTF-8 before returning any output', () => {
  for (const mode of ['clean', 'smudge']) {
    const result = spawnSync(process.execPath, [scriptPath, mode], {
      input: Buffer.from([0x5b, 0x74, 0x6f, 0x63, 0x5d, 0x0a, 0xff]), encoding: 'utf8',
    });
    assert.equal(result.error, undefined);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, '');
    assert.ok(result.stderr.length > 0);
  }
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

test('damaged generated markers stop conversion', () => {
  const broken = [
    `${start}\n<details>\n</details>\n`,
    `${end}\n`,
    `${end}\n${start}\n`,
    `${start}\n<details>\n</details>\n${end}\n${end}\n`,
    `${start}\nNot a disclosure\n${end}\n`,
    `${start}\n<!-- jobs-toc:source {"v":2,"token":"bad-token"} -->\n<details>\n</details>\n${end}\n`,
  ];
  for (const source of broken) assert.throws(() => cleanMarkdown(source), undefined, source);
  assert.throws(() => smudgeMarkdown(`${start}\n`));
});

test('Git stages generated content while worktree and checkout retain the Typora token', t => {
  const repo = temporaryRepository(t);
  const readme = path.join(repo.root, 'README.md');
  const source = '# Filter demo\n\n[toc]\n\n## Install\n\n### Options\n';
  fs.writeFileSync(readme, source);
  const earlier = new Date('2020-01-01T00:00:00Z');
  fs.utimesSync(readme, earlier, earlier);
  repo.git('add', 'README.md');
  const initialIndex = repo.git('show', ':README.md');
  assert.equal(initialIndex, source, 'The index must initially contain the raw Typora token');
  const mtimeBefore = fs.statSync(readme, { bigint: true }).mtimeNs;
  const originalGlobal = fs.readFileSync(repo.globalConfig, 'utf8');
  const installed = repo.cli('install');
  assert.equal(installed.status, 0, installed.stderr);
  assert.equal(repo.git('show', ':README.md'), initialIndex, 'install must not stage anything');
  assert.notEqual(fs.statSync(readme, { bigint: true }).mtimeNs, mtimeBefore, 'install invalidates the tracked document stat cache');
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

test('manifest installation, index checks, checkout, and uninstall cover every listed file', t => {
  const repo = temporaryRepository(t);
  const guide = 'Docs/使用 指南.md';
  const files = ['README.md', guide];
  const sources = {
    'README.md': '# Manifest demo\n\n[toc]\n\n## Main section\n',
    [guide]: '\uFEFF[TOC]\r\n\r\n## 指南第一节\r\n\r\n   [toc] \r\n\r\n### <font id="old-font-id">指南第二节</font>\r\n',
  };
  fs.mkdirSync(path.join(repo.root, '.jobs-markdown-toc'));
  const manifestPath = path.join(repo.root, '.jobs-markdown-toc/manifest.json');
  const manifest = JSON.stringify({ version: 1, files }, null, 2) + '\n';
  fs.writeFileSync(manifestPath, manifest);
  fs.mkdirSync(path.join(repo.root, 'Docs'));
  fs.writeFileSync(path.join(repo.root, '.gitattributes'), `/README.md filter=jobs-markdown-toc\n"/${guide}" filter=jobs-markdown-toc\n`);
  for (const file of files) fs.writeFileSync(path.join(repo.root, file), sources[file]);
  const untouchedPath = path.join(repo.root, 'Docs/unmanaged.md');
  const untouched = '[toc]\n\n## Unmanaged document\n';
  fs.writeFileSync(untouchedPath, untouched);
  const untouchedMtime = fs.statSync(untouchedPath, { bigint: true }).mtimeNs;
  repo.git('add', '--', ...files);
  const indexBefore = Object.fromEntries(files.map(file => [file, repo.git('show', `:${file}`)]));
  const installed = repo.cli('install');
  assert.equal(installed.status, 0, installed.stderr);
  for (const file of files) assert.equal(repo.git('show', `:${file}`), indexBefore[file]);
  assert.equal(fs.readFileSync(untouchedPath, 'utf8'), untouched);
  assert.equal(fs.statSync(untouchedPath, { bigint: true }).mtimeNs, untouchedMtime);
  repo.git('add', '--', ...files);
  for (const file of files) {
    assert.equal(repo.git('show', `:${file}`), cleanMarkdown(sources[file]));
    assert.equal(fs.readFileSync(path.join(repo.root, file), 'utf8'), sources[file]);
  }
  assert.equal(repo.cli('check').status, 0);

  const verified = repo.cli('verify');
  assert.equal(verified.status, 0, verified.stderr);
  const preview = repo.run(process.execPath, ['Scripts/MarkdownToc.mjs', 'preview', guide]);
  assert.equal(preview.status, 0, preview.stderr);
  assert.equal(preview.stdout, cleanMarkdown(sources[guide]));
  for (const file of files) {
    assert.equal(repo.git('show', `:${file}`), cleanMarkdown(sources[file]));
    assert.equal(fs.readFileSync(path.join(repo.root, file), 'utf8'), sources[file]);
  }

  const stale = cleanMarkdown(sources[guide]).replace('>指南第一节</span>', '>已改标题</span>');
  const object = repo.run('git', ['hash-object', '-w', '--stdin'], { input: stale });
  assert.equal(object.status, 0, object.stderr);
  repo.git('update-index', '--cacheinfo', '100644', object.stdout.trim(), guide);
  const checked = repo.cli('check');
  assert.notEqual(checked.status, 0, 'A stale second document must fail the aggregate check');
  repo.git('add', '--', guide);
  assert.equal(repo.cli('check').status, 0);

  repo.git('update-index', '--force-remove', '--', guide);
  assert.notEqual(repo.cli('check').status, 0, 'A missing index entry must fail the aggregate check');
  repo.git('add', '--', guide);
  const invalidObject = repo.run('git', ['hash-object', '-w', '--stdin'], { input: Buffer.from([0xff]) });
  assert.equal(invalidObject.status, 0, invalidObject.stderr);
  repo.git('update-index', '--cacheinfo', '100644', invalidObject.stdout.trim(), guide);
  assert.notEqual(repo.cli('check').status, 0, 'Invalid UTF-8 in any index blob must fail');
  repo.git('add', '--', guide);
  assert.equal(repo.cli('check').status, 0);

  const checkout = path.join(repo.root, 'manifest checkout');
  fs.mkdirSync(checkout);
  repo.git('checkout-index', `--prefix=${checkout}${path.sep}`, '--', ...files);
  for (const file of files) assert.equal(fs.readFileSync(path.join(checkout, file), 'utf8'), sources[file]);

  const indexBeforeUninstall = Object.fromEntries(files.map(file => [file, repo.git('show', `:${file}`)]));
  const removed = repo.cli('uninstall');
  assert.equal(removed.status, 0, removed.stderr);
  for (const file of files) {
    assert.equal(repo.git('show', `:${file}`), indexBeforeUninstall[file]);
    assert.equal(fs.readFileSync(path.join(repo.root, file), 'utf8'), cleanMarkdown(sources[file]));
  }
  assert.equal(fs.readFileSync(manifestPath, 'utf8'), manifest);
  assert.equal(fs.readFileSync(untouchedPath, 'utf8'), untouched);
  assert.equal(fs.statSync(untouchedPath, { bigint: true }).mtimeNs, untouchedMtime);
});

test('invalid manifest paths and schemas fail before installation changes local config', async t => {
  const invalid = [
    { version: 2, files: ['README.md'] },
    { version: 1, files: [] },
    { version: 1, files: 'README.md' },
    { version: 1, files: ['README.md', 'README.md'] },
    { version: 1, files: ['../outside.md'] },
    { version: 1, files: ['/outside.md'] },
    { version: 1, files: ['Docs\\outside.md'] },
  ];
  for (const manifest of invalid) {
    await t.test(JSON.stringify(manifest), sub => {
      const repo = temporaryRepository(sub);
      fs.writeFileSync(path.join(repo.root, 'README.md'), '[toc]\n\n## Section\n');
      fs.mkdirSync(path.join(repo.root, '.jobs-markdown-toc'));
      fs.writeFileSync(path.join(repo.root, '.jobs-markdown-toc/manifest.json'), JSON.stringify(manifest));
      const before = repo.git('config', '--local', '--list');
      assert.notEqual(repo.cli('install').status, 0);
      assert.equal(repo.git('config', '--local', '--list'), before);
    });
  }
});

test('manifest installation does not follow document symlinks or cross nested Git roots', async t => {
  for (const kind of ['symlink', 'nested repository']) {
    await t.test(kind, { skip: kind === 'symlink' && process.platform === 'win32' }, sub => {
      const repo = temporaryRepository(sub);
      const source = '[toc]\n\n## Section\n';
      const target = kind === 'symlink' ? 'Docs/link.md' : 'Docs/Nested/README.md';
      fs.mkdirSync(path.join(repo.root, '.jobs-markdown-toc'));
      fs.mkdirSync(path.join(repo.root, 'Docs'));
      if (kind === 'symlink') {
        fs.writeFileSync(path.join(repo.root, 'Docs/real.md'), source);
        fs.symlinkSync('real.md', path.join(repo.root, target));
      } else {
        repo.git('init', '--quiet', 'Docs/Nested');
        fs.writeFileSync(path.join(repo.root, target), source);
      }
      fs.writeFileSync(path.join(repo.root, '.jobs-markdown-toc/manifest.json'), JSON.stringify({ version: 1, files: [target] }));
      fs.writeFileSync(path.join(repo.root, '.gitattributes'), `/${target} filter=jobs-markdown-toc\n`);
      const before = repo.git('config', '--local', '--list');
      assert.notEqual(repo.cli('install').status, 0);
      assert.equal(repo.git('config', '--local', '--list'), before);
      assert.equal(fs.readFileSync(path.join(repo.root, target), 'utf8'), source);
    });
  }
});

test('index check rejects stale generated content even when worktree content is correct', t => {
  const repo = temporaryRepository(t);
  const source = '[toc]\n\n## Original\n';
  fs.writeFileSync(path.join(repo.root, 'README.md'), source);
  assert.equal(repo.cli('install').status, 0);
  repo.git('add', 'README.md');
  const stale = cleanMarkdown(source).replace('>Original</span>', '>Changed</span>');
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
  const tocHunk = hunks.find(hunk => hunk.includes('[Original](#jobs-toc-heading-1)'));
  const headingHunk = hunks.find(hunk => /\n-## <span[^\n]+>Original<\/span>/.test(hunk));
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
