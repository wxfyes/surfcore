/**
 * SurfCore 移动端（Android / iOS）全自动打包与同步脚本
 *
 * 核心功能：
 * 1. 确保代码变更推送到 GitHub
 * 2. 轮询监控 GitHub Actions 的 [Build iOS IPA] 工作流
 * 3. 打包成功后自动下载最新 IPA Artifact，解压保存到 Windows 桌面！
 * 4. 同步更新局域网小主机的 Android APK
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';

const REPO_OWNER = 'wxfyes';
const REPO_NAME = 'surfcore';
const WORKFLOW_NAME = 'Build iOS IPA';

// 优先从本地私有配置文件读取 Token，防止污染公开提交
function getGitHubToken() {
  const tokenFile = path.join(os.homedir(), '.dsh/surfcore/github_token');
  if (fs.existsSync(tokenFile)) {
    return fs.readFileSync(tokenFile, 'utf8').trim();
  }
  return process.env.GITHUB_TOKEN || '';
}

function getDesktopPath() {
  try {
    const out = execSync('powershell -NoProfile -Command "[Environment]::GetFolderPath(\'Desktop\')"', { encoding: 'utf8' }).trim();
    if (out && fs.existsSync(out)) return out;
  } catch {}
  return path.join(os.homedir(), 'Desktop');
}

async function apiRequest(url, token, options = {}) {
  const headers = {
    'User-Agent': 'surfcore-mobile-build-agent',
    'Accept': 'application/vnd.github+json',
    ...(token ? { 'Authorization': `Bearer ${token}` } : {}),
    ...(options.headers || {})
  };
  return await fetch(url, { ...options, headers });
}

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

export async function runBuildAndFetch() {
  const token = getGitHubToken();
  if (!token) {
    throw new Error('未检测到 GitHub Token，请确保 ~/.dsh/surfcore/github_token 存在');
  }

  const desktop = getDesktopPath();
  console.log(`[Mobile-Build] 目标输出桌面: ${desktop}`);

  // 1. 推送代码
  console.log('[Mobile-Build] 正在推送最新代码至 GitHub main 分支...');
  try {
    execSync('git -c http.proxy=http://127.0.0.1:27890 -c https.proxy=http://127.0.0.1:27890 push origin main', { stdio: 'inherit' });
  } catch (err) {
    console.warn('[Mobile-Build] Git 推送有警告或已是最新:', err.message);
  }

  // 2. 发现或等待最新触发的 workflow run
  console.log('[Mobile-Build] 正在监控 GitHub Actions 构建状态...');
  const currentCommit = execSync('git rev-parse HEAD', { encoding: 'utf8' }).trim();
  console.log(`[Mobile-Build] 本地当前 Commit: ${currentCommit.slice(0, 7)}`);

  let targetRun = null;
  const startTime = Date.now();

  for (let i = 0; i < 25; i++) {
    const res = await apiRequest(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=5`, token);
    if (res.ok) {
      const data = await res.json();
      const runs = (data.workflow_runs || []).filter(r => r.name === WORKFLOW_NAME);
      // 优先寻找匹配当前 commit 的最新 run
      const matched = runs.find(r => r.head_commit?.id === currentCommit || r.head_sha === currentCommit);
      if (matched) {
        targetRun = matched;
        break;
      }
      if (runs.length > 0 && (runs[0].status === 'in_progress' || runs[0].status === 'queued')) {
        targetRun = runs[0];
        break;
      }
    }
    await sleep(2500);
  }

  if (!targetRun) {
    // 若未自动触发，主动调用 dispatch
    console.log('[Mobile-Build] 未检测到自动运行，正在主动触发 workflow_dispatch...');
    await apiRequest(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/workflows/build-mobile-ios.yml/dispatches`, token, {
      method: 'POST',
      body: JSON.stringify({ ref: 'main' })
    });
    await sleep(5000);
    const res = await apiRequest(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1`, token);
    const data = await res.json();
    targetRun = data.workflow_runs?.[0];
  }

  if (!targetRun) {
    throw new Error('未能捕获到 GitHub Actions 构建任务');
  }

  console.log(`[Mobile-Build] 成功锁定构建任务 #${targetRun.run_number} (ID: ${targetRun.id})`);
  console.log(`[Mobile-Build] 构建链接: ${targetRun.html_url}`);

  // 3. 持续轮询构建进度
  let finishedRun = null;
  while (true) {
    const res = await apiRequest(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${targetRun.id}`, token);
    if (!res.ok) {
      await sleep(5000);
      continue;
    }
    const run = await res.json();
    const elapsed = Math.round((Date.now() - startTime) / 1000);

    if (run.status === 'completed') {
      finishedRun = run;
      break;
    }

    console.log(`[Mobile-Build] 正在打包中... 状态: [${run.status}] | 已耗时: ${elapsed}秒`);
    await sleep(8000);
  }

  if (finishedRun.conclusion !== 'success') {
    throw new Error(`[Mobile-Build] iOS IPA 构建未成功完成: ${finishedRun.conclusion}，请检查: ${finishedRun.html_url}`);
  }

  console.log(`[Mobile-Build] 恭喜！GitHub Actions 编译成功完成！(耗时 ${Math.round((Date.now() - startTime) / 1000)}秒)`);

  // 4. 获取产物并下载
  console.log('[Mobile-Build] 正在获取产物 Artifacts 列表...');
  const artRes = await apiRequest(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${finishedRun.id}/artifacts`, token);
  const artData = await artRes.json();
  const artifact = (artData.artifacts || []).find(a => a.name.includes('IPA') || a.name.includes('ipa') || a.name.includes('SurfCore'));

  if (!artifact) {
    throw new Error('未在构建任务中找到 iOS IPA 产物');
  }

  console.log(`[Mobile-Build] 发现产物: ${artifact.name} (${Math.round(artifact.size_in_bytes / 1024 / 1024 * 10) / 10} MB)`);
  console.log('[Mobile-Build] 正在极速下载 IPA 归档包...');

  const downloadRes = await apiRequest(artifact.archive_download_url, token);
  if (!downloadRes.ok) {
    throw new Error(`下载产物失败: ${downloadRes.status} ${downloadRes.statusText}`);
  }

  const tmpZip = path.join(os.tmpdir(), `surfcore_ios_${Date.now()}.zip`);
  const tmpExtract = path.join(os.tmpdir(), `surfcore_ios_extract_${Date.now()}`);
  const arrayBuffer = await downloadRes.arrayBuffer();
  fs.writeFileSync(tmpZip, Buffer.from(arrayBuffer));

  // 5. 解压并投递到桌面
  fs.mkdirSync(tmpExtract, { recursive: true });
  execSync(`powershell -NoProfile -Command "Expand-Archive -LiteralPath '${tmpZip}' -DestinationPath '${tmpExtract}' -Force"`);

  // 寻找解压出的 .ipa 文件
  let ipaFile = null;
  function findIpa(dir) {
    const list = fs.readdirSync(dir);
    for (const item of list) {
      const full = path.join(dir, item);
      if (fs.statSync(full).isDirectory()) findIpa(full);
      else if (item.endsWith('.ipa')) ipaFile = full;
    }
  }
  findIpa(tmpExtract);

  if (!ipaFile) {
    throw new Error('在下载的压缩包中未找到 .ipa 文件');
  }

  const destIpa = path.join(desktop, 'SurfCore伴侣_最新版.ipa');
  fs.copyFileSync(ipaFile, destIpa);

  // 清理临时文件
  try { fs.unlinkSync(tmpZip); } catch {}
  try { fs.rmSync(tmpExtract, { recursive: true, force: true }); } catch {}

  const finalStat = fs.statSync(destIpa);
  console.log('\n========================================================');
  console.log(' [SUCCESS] 最新版 iOS IPA 已自动下载到你的 Windows 桌面！');
  console.log(` 文件路径: ${destIpa}`);
  console.log(` 文件大小: ${Math.round(finalStat.size / 1024 / 1024 * 10) / 10} MB`);
  console.log(' 现在可以使用爱思助手 / 巨魔(TrollStore) / AltStore 签名安装！');
  console.log('========================================================\n');

  // 6. 如果本地存在编译好的 Android APK，自动同步到 FamilySoul/mobile 与小主机
  const scriptDir = path.dirname(new URL(import.meta.url).pathname.replace(/^\/([a-zA-Z]:)/, '$1'));
  const rootDir = path.resolve(scriptDir, '..');
  const localApk = path.resolve(rootDir, 'mobile/build/app/outputs/flutter-apk/app-release.apk');
  if (fs.existsSync(localApk)) {
    const familySoulMobile = 'E:\\GitHub\\FamilySoul\\mobile';
    try {
      if (!fs.existsSync(familySoulMobile)) fs.mkdirSync(familySoulMobile, { recursive: true });
      fs.copyFileSync(localApk, path.join(familySoulMobile, 'SurfCore伴侣_最新版.apk'));
      console.log(`[Mobile-Build] Android APK 已自动同步至: ${familySoulMobile}\\SurfCore伴侣_最新版.apk`);
    } catch (_) {}

    const smbDest = '\\\\192.168.1.213\\H5\\surfcore_family_update\\SurfCore伴侣_最新版.apk';
    try {
      fs.copyFileSync(localApk, smbDest);
      console.log(`[Mobile-Build] Android APK 已自动备份至小主机: ${smbDest}`);
    } catch (_) {}
  }

  return destIpa;
}

// 支持直接运行
if (process.argv[1] && process.argv[1].endsWith('sync-and-build-mobile.mjs')) {
  runBuildAndFetch().catch(err => {
    console.error('\n[Mobile-Build 失败]:', err.message);
    process.exit(1);
  });
}
