#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPORTS_DIR="$SCRIPT_DIR/reports"

usage() {
  cat <<USAGE
Использование:
  bash build-reports-dashboard.sh [reports_dir] [output_dir]

Примеры:
  bash build-reports-dashboard.sh
  bash build-reports-dashboard.sh /path/to/web-audits/reports
  bash build-reports-dashboard.sh /path/to/reports /path/to/output

Скрипт читает готовые папки отчетов web-audits и создает:
  index.html
  summary.txt
  summary.json
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPORTS_DIR="${1:-$DEFAULT_REPORTS_DIR}"
RUN_ID="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_DIR="${2:-$REPORTS_DIR/aggregate-reports/$RUN_ID}"

source_nvm_if_available() {
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.nvm/nvm.sh"
  elif [[ -n "${NVM_DIR:-}" && -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1090
    source "$NVM_DIR/nvm.sh"
  fi
}

source_nvm_if_available
NODE_BIN="$(command -v node || true)"

if [[ -z "$NODE_BIN" ]]; then
  printf 'ERROR: Для сборки сводного отчета нужен Node.js.\n' >&2
  exit 1
fi

"$NODE_BIN" - "$REPORTS_DIR" "$OUTPUT_DIR" <<'NODE'
const fs = require('fs');
const path = require('path');

const [reportsDirArg, outputDirArg] = process.argv.slice(2);
const reportsDir = path.resolve(reportsDirArg);
const outputDir = path.resolve(outputDirArg);
const generatedAt = new Date();

const SCORE_KEYS = [
  ['performance', 'Производительность', '#1d7a8c'],
  ['accessibility', 'Доступность', '#4d7c0f'],
  ['bestPractices', 'Практики', '#7c3aed'],
  ['seo', 'SEO', '#b45309'],
];

const METRIC_KEYS = [
  ['fcp', 'FCP', 'ms'],
  ['lcp', 'LCP', 'ms'],
  ['tbt', 'TBT', 'ms'],
  ['cls', 'CLS', ''],
  ['speedIndex', 'Speed Index', 'ms'],
];

const STATUS_LABELS = {
  completed: 'завершено',
  failed: 'ошибка',
  running: 'в процессе',
  unknown: 'неизвестно',
};

const TEST_TYPE_LABELS = {
  all: 'все',
  lighthouse: 'lighthouse',
  sitespeed: 'sitespeed',
  unknown: 'неизвестно',
};

function fail(message) {
  process.stderr.write(`ERROR: ${message}\n`);
  process.exit(1);
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
  } catch (_) {
    return null;
  }
}

function isDirectory(filePath) {
  try {
    return fs.statSync(filePath).isDirectory();
  } catch (_) {
    return false;
  }
}

function listDirs(dirPath) {
  try {
    return fs.readdirSync(dirPath, {withFileTypes: true})
      .filter(entry => entry.isDirectory())
      .map(entry => path.join(dirPath, entry.name));
  } catch (_) {
    return [];
  }
}

function listFiles(dirPath, predicate) {
  try {
    return fs.readdirSync(dirPath, {withFileTypes: true})
      .filter(entry => entry.isFile() && predicate(entry.name))
      .map(entry => path.join(dirPath, entry.name));
  } catch (_) {
    return [];
  }
}

function findMetadataFiles(rootDir) {
  const result = [];
  const skipDirs = new Set([
    '.git',
    '.lighthouseci',
    '.tools',
    'logs',
    'lighthouse-ci',
    'sitespeed',
    'aggregate-reports',
    'node_modules',
  ]);

  function walk(dirPath, depth) {
    const metadataPath = path.join(dirPath, 'metadata.json');
    if (fs.existsSync(metadataPath)) {
      result.push(metadataPath);
      return;
    }

    if (depth >= 6) return;

    for (const childDir of listDirs(dirPath)) {
      if (skipDirs.has(path.basename(childDir))) continue;
      walk(childDir, depth + 1);
    }
  }

  walk(rootDir, 0);
  return result.sort();
}

function parseRunDate(runId, updatedAt) {
  if (updatedAt) {
    const parsed = new Date(updatedAt);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }

  const match = String(runId || '').match(/^(\d{4})(\d{2})(\d{2})-(\d{2})(\d{2})(\d{2})$/);
  if (match) {
    const [, y, mo, d, h, mi, s] = match;
    return new Date(`${y}-${mo}-${d}T${h}:${mi}:${s}`);
  }

  return null;
}

function formatDate(date) {
  if (!date) return 'unknown';
  return date.toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
}

function domainFromUrl(rawUrl) {
  if (!rawUrl) return '';
  try {
    return new URL(rawUrl).hostname;
  } catch (_) {
    try {
      return new URL(`https://${rawUrl}`).hostname;
    } catch (_) {
      return '';
    }
  }
}

function targetFromUrl(rawUrl, fallback = '') {
  if (!rawUrl) return fallback;
  try {
    const url = new URL(rawUrl);
    url.hash = '';
    return url.href;
  } catch (_) {
    try {
      const url = new URL(`https://${rawUrl}`);
      url.hash = '';
      return url.href;
    } catch (_) {
      return rawUrl || fallback;
    }
  }
}

function parentName(filePath, levels) {
  let current = filePath;
  for (let i = 0; i < levels; i += 1) current = path.dirname(current);
  return path.basename(current);
}

function toScore(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return Math.round(value * 1000) / 10;
}

function cleanNumber(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  return value;
}

function avg(values) {
  const valid = values.filter(value => typeof value === 'number' && Number.isFinite(value));
  if (!valid.length) return null;
  return valid.reduce((sum, value) => sum + value, 0) / valid.length;
}

function round(value, digits = 1) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function pickAuditMetric(lhr, auditId) {
  return cleanNumber(lhr && lhr.audits && lhr.audits[auditId] && lhr.audits[auditId].numericValue);
}

function summarizeLighthouse(runDir) {
  const collectDir = path.join(runDir, 'lighthouse-ci', '.lighthouseci');
  const reportDir = path.join(runDir, 'lighthouse-ci', 'reports');
  const collectLhrFiles = listFiles(collectDir, name => /^lhr-\d+\.json$/.test(name));
  const reportJsonFiles = listFiles(reportDir, name => /\.report\.json$/.test(name));
  const lhrFiles = collectLhrFiles.length ? collectLhrFiles : reportJsonFiles;

  const lhrs = [];
  const seenFiles = new Set();
  for (const filePath of lhrFiles) {
    if (seenFiles.has(filePath)) continue;
    seenFiles.add(filePath);
    const json = readJson(filePath);
    if (json && json.categories) lhrs.push(json);
  }

  const reportHtml = listFiles(reportDir, name => /\.report\.html$/.test(name))[0] || null;
  const manifestPath = path.join(reportDir, 'manifest.json');

  if (!lhrs.length) {
    return {
      available: false,
      reportCount: 0,
      reportHtml,
      manifestPath: fs.existsSync(manifestPath) ? manifestPath : null,
      scores: {},
      metrics: {},
    };
  }

  const scoreValues = {
    performance: lhrs.map(lhr => toScore(lhr.categories.performance && lhr.categories.performance.score)),
    accessibility: lhrs.map(lhr => toScore(lhr.categories.accessibility && lhr.categories.accessibility.score)),
    bestPractices: lhrs.map(lhr => toScore(lhr.categories['best-practices'] && lhr.categories['best-practices'].score)),
    seo: lhrs.map(lhr => toScore(lhr.categories.seo && lhr.categories.seo.score)),
  };

  const metricValues = {
    fcp: lhrs.map(lhr => pickAuditMetric(lhr, 'first-contentful-paint')),
    lcp: lhrs.map(lhr => pickAuditMetric(lhr, 'largest-contentful-paint')),
    tbt: lhrs.map(lhr => pickAuditMetric(lhr, 'total-blocking-time')),
    cls: lhrs.map(lhr => pickAuditMetric(lhr, 'cumulative-layout-shift')),
    speedIndex: lhrs.map(lhr => pickAuditMetric(lhr, 'speed-index')),
  };

  return {
    available: true,
    reportCount: lhrs.length,
    reportHtml,
    manifestPath: fs.existsSync(manifestPath) ? manifestPath : null,
    scores: Object.fromEntries(Object.entries(scoreValues).map(([key, values]) => [key, round(avg(values), 1)])),
    metrics: Object.fromEntries(Object.entries(metricValues).map(([key, values]) => [key, round(avg(values), key === 'cls' ? 3 : 0)])),
  };
}

function numberAt(obj, paths) {
  for (const pathParts of paths) {
    let current = obj;
    for (const part of pathParts) {
      if (!current || typeof current !== 'object' || !(part in current)) {
        current = null;
        break;
      }
      current = current[part];
    }
    if (typeof current === 'number' && Number.isFinite(current)) return current;
  }
  return null;
}

function findSitespeedSummaryFiles(runDir) {
  const sitespeedDir = path.join(runDir, 'sitespeed');
  const wanted = new Set([
    'browsertime.summary-total.json',
    'browsertime.summary.json',
    'coach.summary.json',
  ]);
  const files = [];

  function walk(dirPath, depth) {
    if (depth > 8 || files.length >= 12) return;

    let entries = [];
    try {
      entries = fs.readdirSync(dirPath, {withFileTypes: true});
    } catch (_) {
      return;
    }

    for (const entry of entries) {
      const child = path.join(dirPath, entry.name);
      if (entry.isFile() && wanted.has(entry.name)) files.push(child);
      if (entry.isDirectory()) walk(child, depth + 1);
    }
  }

  if (isDirectory(sitespeedDir)) walk(sitespeedDir, 0);
  return files;
}

function summarizeSitespeed(runDir) {
  const files = findSitespeedSummaryFiles(runDir);
  const summaries = files.map(readJson).filter(Boolean);
  if (!summaries.length) return {available: false, files: [], metrics: {}};

  const metrics = {
    fcp: avg(summaries.map(summary => numberAt(summary, [
      ['statistics', 'timings', 'firstContentfulPaint', 'median'],
      ['statistics', 'timings', 'firstContentfulPaint'],
      ['statistics', 'visualMetrics', 'FirstContentfulPaint', 'median'],
    ]))),
    lcp: avg(summaries.map(summary => numberAt(summary, [
      ['statistics', 'timings', 'largestContentfulPaint', 'median'],
      ['statistics', 'timings', 'largestContentfulPaint'],
      ['statistics', 'visualMetrics', 'LargestContentfulPaint', 'median'],
    ]))),
    speedIndex: avg(summaries.map(summary => numberAt(summary, [
      ['statistics', 'visualMetrics', 'SpeedIndex', 'median'],
      ['statistics', 'timings', 'speedIndex', 'median'],
      ['statistics', 'timings', 'speedIndex'],
    ]))),
    fullyLoaded: avg(summaries.map(summary => numberAt(summary, [
      ['statistics', 'timings', 'fullyLoaded', 'median'],
      ['statistics', 'timings', 'fullyLoaded'],
      ['statistics', 'timings', 'pageCompleteCheck', 'median'],
    ]))),
  };

  return {
    available: true,
    files,
    metrics: Object.fromEntries(Object.entries(metrics).map(([key, value]) => [key, round(value, 0)])),
  };
}

function serverInfoFromMetadata(metadata) {
  const source = metadata.auditSource || {};
  const hostname = source.hostname || 'unknown';
  const publicIp = source.publicIp || 'unknown';
  const localIps = source.localIps || 'unknown';
  const key = hostname !== 'unknown' || publicIp !== 'unknown'
    ? `${hostname} / ${publicIp}`
    : 'unknown';
  return {key, hostname, publicIp, localIps};
}

function relativeLink(filePath) {
  if (!filePath) return '';
  const rel = path.relative(outputDir, filePath).replace(/\\/g, '/');
  return encodeURI(rel || '.');
}

function normalizeStatus(status) {
  const value = String(status || 'unknown').toLowerCase();
  if (['complete', 'completed', 'success', 'ok'].includes(value)) return 'completed';
  if (['failed', 'failure', 'error'].includes(value)) return 'failed';
  if (['running', 'in-progress', 'in_progress'].includes(value)) return 'running';
  return 'unknown';
}

function statusLabel(status) {
  return STATUS_LABELS[status] || status;
}

function testTypeLabel(testType) {
  return TEST_TYPE_LABELS[testType] || testType || TEST_TYPE_LABELS.unknown;
}

function hasLighthouseResult(run) {
  return Boolean(run && run.lighthouse && run.lighthouse.available);
}

function collectRuns() {
  const metadataFiles = findMetadataFiles(reportsDir);
  const runs = [];

  for (const metadataPath of metadataFiles) {
    const metadata = readJson(metadataPath);
    if (!metadata) continue;

    const runDir = path.dirname(metadataPath);
    const runId = metadata.runId || path.basename(runDir);
    const siteSlug = parentName(metadataPath, 2);
    const domain = domainFromUrl(metadata.url) || siteSlug;
    const target = targetFromUrl(metadata.url, domain || siteSlug);
    const timestamp = parseRunDate(runId, metadata.updatedAt);
    const server = serverInfoFromMetadata(metadata);
    const lighthouse = summarizeLighthouse(runDir);
    const sitespeed = summarizeSitespeed(runDir);
    const status = normalizeStatus(metadata.status);
    const testType = metadata.testType || 'unknown';

    runs.push({
      target,
      domain,
      siteSlug,
      url: metadata.url || '',
      runId,
      runDir,
      runLink: relativeLink(runDir),
      reportLink: relativeLink(lighthouse.reportHtml),
      status,
      statusRaw: metadata.status || 'unknown',
      statusLabel: statusLabel(status),
      testType,
      testTypeLabel: testTypeLabel(testType),
      timestamp: timestamp ? timestamp.toISOString() : null,
      timestampMs: timestamp ? timestamp.getTime() : 0,
      timestampLabel: formatDate(timestamp),
      server,
      lighthouse,
      sitespeed,
      metadata,
    });
  }

  return runs.sort((a, b) => a.timestampMs - b.timestampMs || a.target.localeCompare(b.target));
}

function latestByTarget(runs, predicate = () => true, options = {}) {
  const map = new Map();
  const eligibleRuns = runs.filter(predicate);
  const sourceRuns = eligibleRuns.length ? eligibleRuns : (options.fallback === false ? [] : runs);

  for (const run of sourceRuns) {
    const current = map.get(run.target);
    if (!current || run.timestampMs >= current.timestampMs) map.set(run.target, run);
  }
  return Array.from(map.values()).sort((a, b) => a.target.localeCompare(b.target));
}

function latestResultsByTarget(runs) {
  return latestByTarget(runs, hasLighthouseResult, {fallback: false});
}

function groupBy(items, getter) {
  const map = new Map();
  for (const item of items) {
    const key = getter(item);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(item);
  }
  return map;
}

function summarizeRuns(name, runs) {
  const targets = new Set(runs.map(run => run.target));
  const domains = new Set(runs.map(run => run.domain));
  const completed = runs.filter(run => run.status === 'completed').length;
  const failed = runs.filter(run => run.status === 'failed').length;
  const running = runs.filter(run => run.status === 'running').length;
  const lighthouseRuns = runs.filter(run => run.lighthouse.available);

  return {
    name,
    runCount: runs.length,
    targetCount: targets.size,
    domainCount: domains.size,
    completed,
    failed,
    running,
    latest: runs.length ? runs.reduce((latest, run) => run.timestampMs > latest.timestampMs ? run : latest, runs[0]).timestampLabel : 'unknown',
    scores: Object.fromEntries(SCORE_KEYS.map(([key]) => [
      key,
      round(avg(lighthouseRuns.map(run => run.lighthouse.scores[key])), 1),
    ])),
    metrics: Object.fromEntries(METRIC_KEYS.map(([key]) => [
      key,
      round(avg(lighthouseRuns.map(run => run.lighthouse.metrics[key])), key === 'cls' ? 3 : 0),
    ])),
  };
}

function fmt(value, suffix = '') {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 'нет данных';
  return `${value}${suffix}`;
}

function fmtMetric(value, key) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 'нет данных';
  if (key === 'cls') return String(value);
  return `${value} ms`;
}

function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function scoreClass(score) {
  if (typeof score !== 'number') return 'score-none';
  if (score >= 90) return 'score-good';
  if (score >= 50) return 'score-mid';
  return 'score-bad';
}

function scoreCell(score) {
  return `<span class="score-pill ${scoreClass(score)}">${esc(fmt(score))}</span>`;
}

function statGrid(summary) {
  return `
    <div class="stats">
      <div><span>Запусков</span><strong>${summary.runCount}</strong></div>
      <div><span>URL</span><strong>${summary.targetCount}</strong></div>
      <div><span>Доменов</span><strong>${summary.domainCount}</strong></div>
      <div><span>Завершено</span><strong>${summary.completed}</strong></div>
      <div><span>В процессе</span><strong>${summary.running}</strong></div>
      <div><span>Ошибок</span><strong>${summary.failed}</strong></div>
      <div><span>Средняя производительность</span><strong>${fmt(summary.scores.performance)}</strong></div>
      <div><span>Последний запуск</span><strong>${esc(summary.latest)}</strong></div>
    </div>`;
}

function scoreBarChart(title, rows, options = {}) {
  const metrics = options.metrics || SCORE_KEYS;
  const limitedRows = rows.slice(0, options.limit || 40);
  if (!limitedRows.length) return emptySection(title, 'Нет данных для отображения.');

  return `
    <section>
      <div class="section-heading">
        <h2>${esc(title)}</h2>
        ${options.note ? `<p>${esc(options.note)}</p>` : ''}
      </div>
      <div class="bar-chart">
        ${limitedRows.map(row => `
          <div class="bar-row">
            <div class="bar-label" title="${esc(row.label)}">${esc(row.label)}</div>
            <div class="bar-values">
              ${metrics.map(([key, label, color]) => {
                const value = row.values[key];
                const width = typeof value === 'number' ? Math.max(2, Math.min(100, value)) : 0;
                return `
                  <div class="bar-line">
                    <span class="bar-name">${esc(label)}</span>
                    <span class="bar-track">
                      <span class="bar-fill" style="width:${width}%; background:${color};"></span>
                    </span>
                    <span class="bar-number">${esc(fmt(value))}</span>
                  </div>`;
              }).join('')}
            </div>
          </div>`).join('')}
      </div>
    </section>`;
}

function trendChart(title, runs) {
  const byTarget = groupBy(
    runs.filter(run => typeof run.lighthouse.scores.performance === 'number'),
    run => run.target
  );
  const series = Array.from(byTarget.entries())
    .map(([target, targetRuns]) => [target, targetRuns.sort((a, b) => a.timestampMs - b.timestampMs)])
    .filter(([, targetRuns]) => targetRuns.length >= 2)
    .slice(0, 12);

  if (!series.length) {
    return emptySection(title, 'Для графика динамики нужно минимум два Lighthouse-запуска по одному URL.');
  }

  const timestamps = series.flatMap(([, targetRuns]) => targetRuns.map(run => run.timestampMs));
  const minTime = Math.min(...timestamps);
  const maxTime = Math.max(...timestamps);
  const width = 920;
  const height = 320;
  const pad = {left: 54, right: 24, top: 24, bottom: 46};
  const plotW = width - pad.left - pad.right;
  const plotH = height - pad.top - pad.bottom;
  const palette = ['#1d7a8c', '#4d7c0f', '#7c3aed', '#b45309', '#be123c', '#2563eb', '#0f766e', '#9333ea', '#ca8a04', '#0369a1', '#c2410c', '#047857'];

  function x(timestamp) {
    if (minTime === maxTime) return pad.left + plotW / 2;
    return pad.left + ((timestamp - minTime) / (maxTime - minTime)) * plotW;
  }

  function y(score) {
    return pad.top + ((100 - score) / 100) * plotH;
  }

  const axisLines = [0, 50, 90, 100].map(score => {
    const yy = y(score);
    return `<line x1="${pad.left}" y1="${yy}" x2="${width - pad.right}" y2="${yy}" class="grid-line"></line><text x="10" y="${yy + 4}" class="axis-label">${score}</text>`;
  }).join('');

  const paths = series.map(([target, targetRuns], index) => {
    const color = palette[index % palette.length];
    const points = targetRuns.map(run => [x(run.timestampMs), y(run.lighthouse.scores.performance), run]);
    const pathData = points.map(([px, py], pointIndex) => `${pointIndex === 0 ? 'M' : 'L'} ${px.toFixed(1)} ${py.toFixed(1)}`).join(' ');
    return `
      <path d="${pathData}" fill="none" stroke="${color}" stroke-width="2.5"></path>
      ${points.map(([px, py, run]) => `<circle cx="${px.toFixed(1)}" cy="${py.toFixed(1)}" r="3.5" fill="${color}"><title>${esc(target)}: ${fmt(run.lighthouse.scores.performance)} на ${esc(run.timestampLabel)}</title></circle>`).join('')}`;
  }).join('');

  const legend = series.map(([target], index) => {
    const color = palette[index % palette.length];
    return `<span><i style="background:${color}"></i>${esc(target)}</span>`;
  }).join('');

  return `
    <section>
      <div class="section-heading">
        <h2>${esc(title)}</h2>
        <p>Динамика оценки производительности. На график попадает до 12 URL, у которых есть минимум два готовых Lighthouse-запуска. Если здесь один URL, значит только по нему сейчас достаточно точек для линии.</p>
      </div>
      <svg class="trend-chart" viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(title)}">
        <rect x="0" y="0" width="${width}" height="${height}" rx="8" class="chart-bg"></rect>
        ${axisLines}
        <line x1="${pad.left}" y1="${pad.top}" x2="${pad.left}" y2="${height - pad.bottom}" class="axis-line"></line>
        <line x1="${pad.left}" y1="${height - pad.bottom}" x2="${width - pad.right}" y2="${height - pad.bottom}" class="axis-line"></line>
        ${paths}
      </svg>
      <div class="legend">${legend}</div>
    </section>`;
}

function emptySection(title, message) {
  return `
    <section>
      <div class="section-heading"><h2>${esc(title)}</h2></div>
      <p class="empty">${esc(message)}</p>
    </section>`;
}

function latestRowsTable(title, rows) {
  if (!rows.length) return emptySection(title, 'Нет данных для отображения.');

  return `
    <section>
      <div class="section-heading"><h2>${esc(title)}</h2></div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>URL</th>
              <th>Последний результат</th>
              <th>Сервер</th>
              <th>Статус</th>
              <th>Perf</th>
              <th>A11y</th>
              <th>BP</th>
              <th>SEO</th>
              <th>LCP</th>
              <th>TBT</th>
            </tr>
          </thead>
          <tbody>
            ${rows.map(run => `
              <tr>
                <td><strong>${esc(run.target)}</strong><br><span>${esc(run.domain)}</span></td>
                <td>${esc(run.timestampLabel)}<br><span>${esc(run.runId)}</span></td>
                <td>${esc(run.server.key)}</td>
                <td><span class="status status-${esc(run.status)}">${esc(run.statusLabel)}</span><br><span>${esc(run.testTypeLabel)}</span></td>
                <td>${scoreCell(run.lighthouse.scores.performance)}</td>
                <td>${scoreCell(run.lighthouse.scores.accessibility)}</td>
                <td>${scoreCell(run.lighthouse.scores.bestPractices)}</td>
                <td>${scoreCell(run.lighthouse.scores.seo)}</td>
                <td>${esc(fmtMetric(run.lighthouse.metrics.lcp, 'lcp'))}</td>
                <td>${esc(fmtMetric(run.lighthouse.metrics.tbt, 'tbt'))}</td>
              </tr>`).join('')}
          </tbody>
        </table>
      </div>
    </section>`;
}

function allRunsTable(title, rows) {
  if (!rows.length) return emptySection(title, 'Нет данных для отображения.');

  return `
    <section>
      <div class="section-heading"><h2>${esc(title)}</h2></div>
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>URL</th>
              <th>Запуск</th>
              <th>Сервер</th>
              <th>Статус</th>
              <th>Lighthouse прогонов</th>
              <th>Perf</th>
              <th>FCP</th>
              <th>LCP</th>
              <th>CLS</th>
              <th>sitespeed Fully Loaded</th>
            </tr>
          </thead>
          <tbody>
            ${rows.slice().reverse().map(run => `
              <tr>
                <td>${esc(run.target)}<br><span>${esc(run.domain)}</span></td>
                <td>${esc(run.timestampLabel)}<br><span>${esc(run.runId)}</span></td>
                <td>${esc(run.server.key)}</td>
                <td><span class="status status-${esc(run.status)}">${esc(run.statusLabel)}</span><br><span>${esc(run.testTypeLabel)}</span></td>
                <td>${run.lighthouse.reportCount || 0}</td>
                <td>${scoreCell(run.lighthouse.scores.performance)}</td>
                <td>${esc(fmtMetric(run.lighthouse.metrics.fcp, 'fcp'))}</td>
                <td>${esc(fmtMetric(run.lighthouse.metrics.lcp, 'lcp'))}</td>
                <td>${esc(fmtMetric(run.lighthouse.metrics.cls, 'cls'))}</td>
                <td>${esc(fmtMetric(run.sitespeed.metrics.fullyLoaded, 'fullyLoaded'))}</td>
              </tr>`).join('')}
          </tbody>
        </table>
      </div>
    </section>`;
}

function serverSections(runs) {
  const groups = Array.from(groupBy(runs, run => run.server.key).entries())
    .sort(([a], [b]) => a.localeCompare(b));

  return groups.map(([serverKey, serverRuns]) => {
    const summary = summarizeRuns(serverKey, serverRuns);
    const latest = latestResultsByTarget(serverRuns);
    const chartRows = latest
      .map(run => ({label: run.target, values: run.lighthouse.scores}))
      .sort((a, b) => (b.values.performance ?? -1) - (a.values.performance ?? -1));

    return `
      <section class="server-section">
        <div class="section-heading">
          <h2>Сервер: ${esc(serverKey)}</h2>
          <p>Группировка берется из блока <code>auditSource</code> в каждом <code>metadata.json</code>.</p>
        </div>
        ${statGrid(summary)}
        ${scoreBarChart(`Последние оценки URL на ${serverKey}`, chartRows, {limit: 30})}
        ${latestRowsTable(`Последние результаты на ${serverKey}`, latest)}
      </section>`;
  }).join('');
}

function textTable(rows, columns) {
  const widths = columns.map(column => Math.max(
    column.label.length,
    ...rows.map(row => String(column.value(row)).length)
  ));
  const line = columns.map((column, index) => column.label.padEnd(widths[index])).join('  ');
  const sep = widths.map(width => '-'.repeat(width)).join('  ');
  const body = rows.map(row => columns.map((column, index) => String(column.value(row)).padEnd(widths[index])).join('  '));
  return [line, sep, ...body].join('\n');
}

function buildTextReport(runs, latest, serverSummaries, overall) {
  const latestColumns = [
    {label: 'URL', value: run => run.target},
    {label: 'Домен', value: run => run.domain},
    {label: 'Дата', value: run => run.timestampLabel},
    {label: 'Сервер', value: run => run.server.key},
    {label: 'Статус', value: run => run.statusLabel},
    {label: 'Perf', value: run => fmt(run.lighthouse.scores.performance)},
    {label: 'A11y', value: run => fmt(run.lighthouse.scores.accessibility)},
    {label: 'BP', value: run => fmt(run.lighthouse.scores.bestPractices)},
    {label: 'SEO', value: run => fmt(run.lighthouse.scores.seo)},
    {label: 'LCP', value: run => fmtMetric(run.lighthouse.metrics.lcp, 'lcp')},
    {label: 'TBT', value: run => fmtMetric(run.lighthouse.metrics.tbt, 'tbt')},
  ];

  const serverColumns = [
    {label: 'Сервер', value: row => row.name},
    {label: 'Запусков', value: row => row.runCount},
    {label: 'URL', value: row => row.targetCount},
    {label: 'Доменов', value: row => row.domainCount},
    {label: 'Завершено', value: row => row.completed},
    {label: 'В процессе', value: row => row.running},
    {label: 'Ошибок', value: row => row.failed},
    {label: 'Ср. Perf', value: row => fmt(row.scores.performance)},
    {label: 'Ср. LCP', value: row => fmtMetric(row.metrics.lcp, 'lcp')},
  ];

  return [
    'Сводный отчет Web Audits',
    `Создан: ${formatDate(generatedAt)}`,
    `Папка с отчетами: ${reportsDir}`,
    `Папка результата: ${outputDir}`,
    '',
    'Общая сводка',
    `Запусков: ${overall.runCount}`,
    `URL: ${overall.targetCount}`,
    `Доменов: ${overall.domainCount}`,
    `Завершено: ${overall.completed}`,
    `В процессе: ${overall.running}`,
    `Ошибок: ${overall.failed}`,
    `Средняя производительность: ${fmt(overall.scores.performance)}`,
    `Средний LCP: ${fmtMetric(overall.metrics.lcp, 'lcp')}`,
    '',
    'Последние результаты по URL',
    latest.length ? textTable(latest, latestColumns) : 'Данные по URL не найдены.',
    '',
    'Серверы',
    serverSummaries.length ? textTable(serverSummaries, serverColumns) : 'Данные по серверам не найдены.',
    '',
    'Все запуски',
    runs.length ? textTable(runs.slice().reverse(), [
      {label: 'URL', value: run => run.target},
      {label: 'Домен', value: run => run.domain},
      {label: 'Запуск', value: run => run.runId},
      {label: 'Дата', value: run => run.timestampLabel},
      {label: 'Сервер', value: run => run.server.key},
      {label: 'Статус', value: run => run.statusLabel},
      {label: 'Perf', value: run => fmt(run.lighthouse.scores.performance)},
    ]) : 'Запуски не найдены.',
    '',
  ].join('\n');
}

function buildHtml(runs) {
  const latest = latestResultsByTarget(runs);
  const overall = summarizeRuns('Общий итог', runs);
  const serverSummaries = Array.from(groupBy(runs, run => run.server.key).entries())
    .map(([serverKey, serverRuns]) => summarizeRuns(serverKey, serverRuns))
    .sort((a, b) => a.name.localeCompare(b.name));

  const latestChartRows = latest
    .map(run => ({label: run.target, values: run.lighthouse.scores}))
    .sort((a, b) => (b.values.performance ?? -1) - (a.values.performance ?? -1));

  const serverChartRows = serverSummaries
    .map(summary => ({label: summary.name, values: summary.scores}))
    .sort((a, b) => (b.values.performance ?? -1) - (a.values.performance ?? -1));

  const textReport = buildTextReport(runs, latest, serverSummaries, overall);

  const html = `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Сводный отчет Web Audits</title>
  <style>
    :root {
      --bg: #f6f8fb;
      --panel: #ffffff;
      --text: #172033;
      --muted: #667085;
      --border: #d8dee9;
      --good: #15803d;
      --mid: #b45309;
      --bad: #b91c1c;
      --none: #64748b;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      color: var(--text);
      background: var(--bg);
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }
    header {
      padding: 28px 32px 18px;
      border-bottom: 1px solid var(--border);
      background: #ffffff;
    }
    main { padding: 24px 32px 44px; }
    h1, h2, h3 { margin: 0; line-height: 1.15; letter-spacing: 0; }
    h1 { font-size: 28px; }
    h2 { font-size: 18px; }
    p { color: var(--muted); margin: 8px 0 0; }
    code { background: #eef2f7; padding: 2px 5px; border-radius: 4px; }
    a { color: #1d4ed8; text-decoration: none; }
    a:hover { text-decoration: underline; }
    section {
      margin-top: 18px;
      padding: 18px;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
    }
    .server-section {
      padding: 0;
      background: transparent;
      border: 0;
    }
    .server-section > .section-heading,
    .server-section > .stats,
    .server-section > section {
      margin-top: 18px;
    }
    .meta {
      display: flex;
      gap: 16px;
      flex-wrap: wrap;
      margin-top: 14px;
      color: var(--muted);
    }
    .stats {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 10px;
    }
    .stats > div {
      padding: 12px;
      border: 1px solid var(--border);
      border-radius: 8px;
      background: #fff;
    }
    .stats span {
      display: block;
      color: var(--muted);
      font-size: 12px;
      margin-bottom: 5px;
    }
    .stats strong { font-size: 20px; }
    .bar-chart { display: grid; gap: 12px; }
    .bar-row {
      display: grid;
      grid-template-columns: minmax(150px, 240px) 1fr;
      gap: 12px;
      align-items: start;
      padding-bottom: 12px;
      border-bottom: 1px solid #edf0f5;
    }
    .bar-row:last-child { border-bottom: 0; padding-bottom: 0; }
    .bar-label {
      font-weight: 650;
      overflow-wrap: anywhere;
    }
    .bar-values { display: grid; gap: 6px; }
    .bar-line {
      display: grid;
      grid-template-columns: 104px 1fr 52px;
      gap: 8px;
      align-items: center;
    }
    .bar-name, .bar-number {
      color: var(--muted);
      font-size: 12px;
    }
    .bar-number { text-align: right; }
    .bar-track {
      height: 10px;
      border-radius: 99px;
      overflow: hidden;
      background: #e7ebf2;
    }
    .bar-fill {
      display: block;
      height: 100%;
      border-radius: inherit;
    }
    .table-wrap { overflow-x: auto; }
    table {
      width: 100%;
      border-collapse: collapse;
      min-width: 980px;
    }
    th, td {
      padding: 10px 9px;
      border-bottom: 1px solid #edf0f5;
      text-align: left;
      vertical-align: top;
    }
    th {
      color: #344054;
      font-size: 12px;
      text-transform: uppercase;
      letter-spacing: .04em;
      background: #f9fafc;
    }
    td span { color: var(--muted); font-size: 12px; }
    .score-pill {
      display: inline-flex;
      min-width: 44px;
      justify-content: center;
      border-radius: 999px;
      padding: 3px 8px;
      color: #fff;
      font-weight: 700;
      font-size: 12px;
    }
    .score-good { background: var(--good); }
    .score-mid { background: var(--mid); }
    .score-bad { background: var(--bad); }
    .score-none { background: var(--none); }
    .status {
      display: inline-flex;
      border-radius: 999px;
      padding: 3px 8px;
      color: #fff;
      font-weight: 700;
      font-size: 12px;
      background: var(--none);
    }
    .status-completed { background: var(--good); }
    .status-running { background: var(--mid); }
    .status-failed { background: var(--bad); }
    .trend-chart {
      display: block;
      width: 100%;
      height: auto;
      margin-top: 12px;
    }
    .chart-bg { fill: #fbfcff; stroke: var(--border); }
    .grid-line { stroke: #e5eaf2; stroke-width: 1; }
    .axis-line { stroke: #aab4c3; stroke-width: 1; }
    .axis-label { fill: var(--muted); font-size: 12px; }
    .legend {
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin-top: 10px;
      color: var(--muted);
      font-size: 12px;
    }
    .legend span { display: inline-flex; align-items: center; gap: 5px; }
    .legend i { width: 10px; height: 10px; border-radius: 50%; display: inline-block; }
    .empty { padding: 12px; background: #f9fafc; border-radius: 8px; }
    pre {
      white-space: pre-wrap;
      overflow-wrap: anywhere;
      margin: 0;
      padding: 14px;
      background: #0f172a;
      color: #e5eefb;
      border-radius: 8px;
      font-size: 12px;
    }
    @media (max-width: 760px) {
      header, main { padding-left: 16px; padding-right: 16px; }
      .bar-row { grid-template-columns: 1fr; }
      .bar-line { grid-template-columns: 86px 1fr 44px; }
    }
  </style>
</head>
<body>
  <header>
    <h1>Сводный отчет Web Audits</h1>
    <div class="meta">
      <span>Создан: ${esc(formatDate(generatedAt))}</span>
      <span>Источник: <code>${esc(reportsDir)}</code></span>
      <span>Запусков: ${runs.length}</span>
      <span>URL с результатами: ${latest.length}</span>
    </div>
  </header>
  <main>
    <section>
      <div class="section-heading">
        <h2>Общая сводка</h2>
        <p>Оценки считаются по сохраненным JSON-результатам Lighthouse. Последние строки по URL берут самый свежий запуск, где уже есть реальные Lighthouse-данные.</p>
      </div>
      ${statGrid(overall)}
    </section>
    ${scoreBarChart('Последние оценки по URL', latestChartRows, {limit: 40})}
    ${scoreBarChart('Средние оценки по серверам проверки', serverChartRows, {limit: 40})}
    ${trendChart('Динамика производительности по URL', runs)}
    ${latestRowsTable('Последние результаты по URL', latest)}
    ${serverSections(runs)}
    ${allRunsTable('Все запуски', runs)}
    <section>
      <div class="section-heading">
        <h2>Текстовая сводка</h2>
        <p>Та же сводка записывается в <code>summary.txt</code>.</p>
      </div>
      <pre>${esc(textReport)}</pre>
    </section>
  </main>
</body>
</html>`;

  return {html, textReport, latest, serverSummaries, overall};
}

if (!isDirectory(reportsDir)) fail(`Папка с отчетами не найдена: ${reportsDir}`);

const runs = collectRuns();
if (!runs.length) fail(`Внутри папки не найдены metadata.json: ${reportsDir}`);

const built = buildHtml(runs);
fs.mkdirSync(outputDir, {recursive: true});
fs.writeFileSync(path.join(outputDir, 'index.html'), built.html);
fs.writeFileSync(path.join(outputDir, 'summary.txt'), built.textReport);
fs.writeFileSync(path.join(outputDir, 'summary.json'), JSON.stringify({
  generatedAt: generatedAt.toISOString(),
  reportsDir,
  outputDir,
  overall: built.overall,
  servers: built.serverSummaries,
  latestByUrl: built.latest,
  latestByDomain: built.latest,
  runs,
}, null, 2));

process.stdout.write(`Сводный отчет создан:\n`);
process.stdout.write(`  ${path.join(outputDir, 'index.html')}\n`);
process.stdout.write(`  ${path.join(outputDir, 'summary.txt')}\n`);
process.stdout.write(`  ${path.join(outputDir, 'summary.json')}\n`);
NODE
